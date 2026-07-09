import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:dio/dio.dart';
import '../../core/services/storage_service.dart';
import 'package:flutter/foundation.dart';

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
      final res = await _dio.post('/v1/auth/firebase/verify', data: {
        'idToken': idToken,
        'deviceId': 'flutter_app',
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

  Future<void> signOut() async {
    await _auth.signOut();
    await StorageService.clearAll();
  }
}