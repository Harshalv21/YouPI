import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dio/dio.dart';
import '../../core/services/storage_service.dart';
import 'package:flutter/foundation.dart';

/// Result of a `/v1/auth/mpin/verify` attempt. Kept structured (instead of
/// just throwing a string) because the Login-via-MPIN screen needs to branch
/// on the exact backend error code -- wrong PIN (retry in place) vs locked
/// out / MPIN never set / mobile not registered (all three need to fall back
/// to the OTP-recovery flow), vs an inactive account (dead end).
class MpinLoginResult {
  final bool success;
  final String? errorCode; // MPIN_INVALID | MPIN_LOCKED | MPIN_NOT_SET | USER_NOT_FOUND | USER_INACTIVE | null
  final String? message;
  final int? attemptsRemaining; // only set for MPIN_INVALID
  final bool isNewUser;
  final bool profileComplete;

  MpinLoginResult({
    required this.success,
    this.errorCode,
    this.message,
    this.attemptsRemaining,
    this.isNewUser = false,
    this.profileComplete = false,
  });

  /// These four codes all mean "we can't trust this MPIN-only attempt
  /// anymore, but the mobile number itself is fine to send an OTP to" -- so
  /// the screen can treat them identically: send OTP, push to /auth/otp, let
  /// the existing isNewUser/profileComplete branch there route correctly
  /// afterwards. DEVICE_NOT_TRUSTED in particular means the MPIN was
  /// actually CORRECT -- this device just hasn't proven itself via OTP yet;
  /// once it does, the backend auto-trusts it and MPIN-only login will work
  /// here going forward.
  bool get shouldFallBackToOtp =>
      errorCode == 'MPIN_LOCKED' ||
          errorCode == 'MPIN_NOT_SET' ||
          errorCode == 'USER_NOT_FOUND' ||
          errorCode == 'DEVICE_NOT_TRUSTED';
}

class AuthRepository {
  static final AuthRepository _instance = AuthRepository._internal();
  factory AuthRepository() => _instance;

  AuthRepository._internal() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await StorageService.getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ));
  }

  final FirebaseAuth _auth = FirebaseAuth.instance;
  // Same base URL as ApiService - keep these in sync. Configurable via
  // --dart-define=API_BASE_URL=... for local testing; defaults to Cloud Run.
  final Dio _dio = Dio(BaseOptions(baseUrl: const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://youpi-api-887162129478.asia-south1.run.app/api',
  )));
  String? _verificationId;
  int? _resendToken;

  Future<bool> sendOtp(String mobile) async {
    final completer = Completer<bool>();

    await _auth.verifyPhoneNumber(
      phoneNumber: '+91$mobile',
      timeout: const Duration(seconds: 60),
      // Use Firebase's own resend token on repeat calls (i.e. "Resend OTP")
      // instead of always starting a brand-new verification attempt.
      forceResendingToken: _resendToken,
      verificationCompleted: (PhoneAuthCredential credential) async {
        print('🟢 verificationCompleted (auto)');
        await _auth.signInWithCredential(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        print('🔴 verificationFailed: ${e.code} — ${e.message}');
        if (!completer.isCompleted) {
          completer.completeError(Exception('${e.code}: ${e.message}'));
        }
      },
      codeSent: (String verificationId, int? resendToken) {
        print('🟡 codeSent OK');
        _verificationId = verificationId;
        _resendToken = resendToken;
        if (!completer.isCompleted) completer.complete(true);
      },
      codeAutoRetrievalTimeout: (String verificationId) {
        print('⏱️ autoRetrievalTimeout');
        _verificationId = verificationId;
      },
    );

    return completer.future;
  }

  Future<Map<String, dynamic>?> verifyOtp(String mobile, String otp) async {
    if (_verificationId == null) throw Exception('send Otp');

    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: otp,
    );
    final userCred = await _auth.signInWithCredential(credential);
    final idToken = await userCred.user?.getIdToken();
    if (idToken == null) throw Exception('Firebase token not Found');

    try {
      final deviceId = await StorageService.getOrCreateDeviceId();
      final res = await _dio.post('/v1/auth/firebase/verify', data: {
        'idToken': idToken,
        'deviceId': deviceId,
      });

      if (res.data is! Map) {
        debugPrint('🔴 Unexpected response type: ${res.data.runtimeType}');
        debugPrint('🔴 Raw response (first 300 chars): '
            '${res.data.toString().substring(0, res.data.toString().length > 300 ? 300 : res.data.toString().length)}');
        throw Exception(
            'Server did not return a valid response. This usually means the '
                'API is blocking unauthenticated requests (Cloud Run access '
                'control) rather than a login problem.');
      }

      if (res.data?['success'] == true) {
        final data = res.data['data'];
        // Save BOTH tokens now (access + refresh) for seamless sessions.
        await StorageService.saveTokens(
          accessToken: data['accessToken'],
          refreshToken: data['refreshToken'],
        );
        // Remember this number so LoginMpinScreen can skip straight to the
        // MPIN pad next time instead of asking for it again on this device.
        await StorageService.saveLastMobile(mobile);
        return {
          'isNewUser': data['isNewUser'] ?? false,
          'profileComplete': data['profileComplete'] ?? false,
          'kycStatus': data['kycStatus'] ?? 'PENDING',
        };
      }
      return null;
    } on DioException catch (e) {
      print('🔴 BACKEND: ${e.response?.statusCode} — ${e.response?.data}');
      throw Exception(e.response?.data?['error']?['message'] ?? 'Verify fail');
    }
  }

  /// MPIN backend pe save karo. Token interceptor auto Bearer laga dega.
  Future<void> setupMpin(String mpin) async {
    final res = await _dio.post('/v1/auth/mpin/setup', data: {
      'mpin': mpin,
    });
    if (res.data?['success'] != true) {
      throw Exception(res.data?['error']?['message'] ?? 'MPIN setup failed');
    }
  }

  /// "Existing User" login path -- verifies mobile+MPIN directly against the
  /// backend (POST /v1/auth/mpin/verify), bypassing OTP entirely on success.
  /// Attempt-count/lockout is enforced server-side (UserMpinRepository), so
  /// this NEVER trusts a locally-held attempts counter -- a reinstall can't
  /// reset it.
  Future<MpinLoginResult> loginWithMpin(String mobile, String mpin) async {
    try {
      final deviceId = await StorageService.getOrCreateDeviceId();
      final res = await _dio.post('/v1/auth/mpin/verify', data: {
        'mobile': mobile,
        'mpin': mpin,
        'deviceId': deviceId,
      });

      if (res.data?['success'] == true) {
        final data = res.data['data'];
        await StorageService.saveTokens(
          accessToken: data['accessToken'],
          refreshToken: data['refreshToken'],
        );
        await StorageService.saveLastMobile(mobile);
        return MpinLoginResult(
          success: true,
          isNewUser: data['isNewUser'] ?? false,
          profileComplete: data['profileComplete'] ?? false,
        );
      }
      return MpinLoginResult(success: false, message: 'Unexpected response from server.');
    } on DioException catch (e) {
      final errBody = e.response?.data;
      final err = (errBody is Map && errBody['error'] is Map) ? errBody['error'] as Map : null;
      final code = err?['code'] as String?;
      final message = (err?['message'] as String?) ?? e.message ?? 'Login failed';

      // MpinMismatchException's message looks like "Invalid MPIN. 3 attempts
      // remaining." -- the backend's ApiResponse envelope doesn't carry a
      // separate structured field for this, so we parse it out of the
      // message rather than requiring a backend change.
      int? attemptsRemaining;
      if (code == 'MPIN_INVALID') {
        final match = RegExp(r'(\d+)\s+attempts?\s+remaining').firstMatch(message);
        if (match != null) attemptsRemaining = int.tryParse(match.group(1)!);
      }

      return MpinLoginResult(
        success: false,
        errorCode: code,
        message: message,
        attemptsRemaining: attemptsRemaining,
      );
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await StorageService.clearAll();
  }
}