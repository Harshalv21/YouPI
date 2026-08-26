// lib/data/repositories/user_repository.dart
//
// Real backend-connected user repository.
// Endpoints (Bearer token auto-added by ApiService):
//   GET  /v1/user/profile          -> profile
//   PUT  /v1/user/profile          -> update name/email/dob
//   GET  /v1/user/kyc/status       -> KYC status
//   POST /v1/user/kyc/aadhaar/otp    -> Aadhaar OTP send (mocked Digio)
//   POST /v1/user/kyc/aadhaar/verify -> Aadhaar OTP verify (mocked Digio)
//   POST /v1/user/kyc/pan/verify   -> PAN verification (via Eko)
//   POST /v1/user/kyc/bank/verify  -> Bank account verification (via Eko)

import 'package:dio/dio.dart';
import '../../core/services/api_service.dart';
import '../models/user_model.dart';
import 'package:flutter/foundation.dart';

/// Result of a PAN verification call -- carries the name Eko matched
/// against the PAN, so the UI can show the user what was found (and let
/// them notice a mismatch before continuing).
class PanVerifyResult {
  final bool verified;
  final String? nameOnPan;
  PanVerifyResult({required this.verified, this.nameOnPan});
}

/// Result of a bank account verification call.
class BankVerifyResult {
  final bool verified;
  final String? accountHolderName;
  final String? bankName;
  final String? branch;
  BankVerifyResult({
    required this.verified,
    this.accountHolderName,
    this.bankName,
    this.branch,
  });
}
class KycDetailsResult {
  final String kycStatus;
  final bool aadhaarVerified;
  final bool panVerified;
  final String? panNumberMasked;
  final String? panHolderName;
  final bool bankVerified;
  final String? bankAccountLast4;
  final String? bankIfsc;
  final String? bankName;
  final String? bankAccountHolderName;

  KycDetailsResult({
    required this.kycStatus,
    required this.aadhaarVerified,
    required this.panVerified,
    this.panNumberMasked,
    this.panHolderName,
    required this.bankVerified,
    this.bankAccountLast4,
    this.bankIfsc,
    this.bankName,
    this.bankAccountHolderName,
  });

  factory KycDetailsResult.fromJson(Map<String, dynamic> j) => KycDetailsResult(
    kycStatus: (j['kycStatus'] ?? 'PENDING').toString(),
    aadhaarVerified: j['aadhaarVerified'] == true,
    panVerified: j['panVerified'] == true,
    panNumberMasked: j['panNumberMasked']?.toString(),
    panHolderName: j['panHolderName']?.toString(),
    bankVerified: j['bankVerified'] == true,
    bankAccountLast4: j['bankAccountLast4']?.toString(),
    bankIfsc: j['bankIfsc']?.toString(),
    bankName: j['bankName']?.toString(),
    bankAccountHolderName: j['bankAccountHolderName']?.toString(),
  );
}
class UserRepository {
  final Dio _dio = ApiService.instance;

  /// Fetch the logged-in user's profile.
  Future<UserModel> getProfile() async {
    try {
      final res = await _dio.get('/v1/user/profile');
      final data = ApiService.unwrap(res);
      return UserModel.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }

  /// Update profile. dateOfBirth expected as ISO date string 'yyyy-MM-dd'.
  Future<UserModel> updateProfile({
    String? fullName,
    String? email,
    String? dateOfBirth,
  }) async {
    try {
      final res = await _dio.put('/v1/user/profile', data: {
        if (fullName != null) 'fullName': fullName,
        if (email != null) 'email': email,
        if (dateOfBirth != null) 'dateOfBirth': dateOfBirth,
      });
      debugPrint('RAW RESPONSE: ${res.data}');
      final data = ApiService.unwrap(res);
      return UserModel.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }

  /// KYC status string: 'verified' | 'pending' | 'rejected' (normalized lowercase).
  Future<String> getKycStatus() async {
    try {
      final res = await _dio.get('/v1/user/kyc/status');
      final data = ApiService.unwrap(res);
      if (data is Map) {
        final s = (data['status'] ?? data['kycStatus'])?.toString();
        if (s != null && s.isNotEmpty) return s.toLowerCase();
        if (data['isKycVerified'] == true) return 'verified';
      }
      return 'pending';
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }

  }

  /// Sends Aadhaar OTP via backend (mocked Digio under the hood for now --
  /// always succeeds server-side, but the call is real and creates the
  /// kyc_records row via getOrCreateKyc() so downstream PAN/Bank verify
  /// can find it). Returns the digioRequestId needed for the verify call.
  Future<String> initiateAadhaarOtp(String aadhaarNumber) async {
    try {
      final res = await _dio.post('/v1/user/kyc/aadhaar/otp', data: {
        'aadhaarNumber': aadhaarNumber,
      });
      final data = ApiService.unwrap(res);
      return (data as Map)['digioRequestId'].toString();
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }

  /// Verifies the Aadhaar OTP via backend -- moves kycStatus to AADHAAR_DONE.
  Future<bool> verifyAadhaarOtp({
    required String aadhaarNumber,
    required String otp,
    required String digioRequestId,
  }) async {
    try {
      final res = await _dio.post('/v1/user/kyc/aadhaar/verify', data: {
        'aadhaarNumber': aadhaarNumber,
        'otp': otp,
        'digioRequestId': digioRequestId,
      });
      ApiService.unwrap(res);
      return true;
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }

  /// Verifies a PAN number via the backend (Eko fetch-pan under the hood).
  /// Throws on network/server error; a "PAN not found"-type rejection from
  /// Eko comes back as a normal failed-Result on the backend, surfaced here
  /// as a thrown exception (via ApiService.toException) same as any other
  /// 4xx -- caller should catch and show the message.
  Future<PanVerifyResult> verifyPan(String panNumber) async {
    try {
      final res = await _dio.post('/v1/user/kyc/pan/verify', data: {
        'panNumber': panNumber,
      });
      final data = ApiService.unwrap(res);
      if (data is Map) {
        return PanVerifyResult(
          verified: data['panVerified'] == true,
          nameOnPan: data['panHolderName']?.toString(),
        );
      }
      return PanVerifyResult(verified: false);
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }

  /// Verifies a bank account number + IFSC via the backend (Eko
  /// bank-account/sync under the hood). Independent of the Aadhaar/PAN/
  /// Selfie sequence -- see UserService.kt's verifyBankAccount() doc
  /// comment on the backend side.
  Future<BankVerifyResult> verifyBankAccount({
    required String accountNumber,
    required String ifsc,
  }) async {
    try {
      final res = await _dio.post('/v1/user/kyc/bank/verify', data: {
        'accountNumber': accountNumber,
        'ifsc': ifsc,
      });
      final data = ApiService.unwrap(res);
      if (data is Map) {
        return BankVerifyResult(
          verified: data['bankVerified'] == true,
          accountHolderName: data['bankAccountHolderName']?.toString(),
        );
      }
      return BankVerifyResult(verified: false);
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }

  /// Full KYC details for the Settings > PAN Details / Bank Details screens
  /// (GPay/PhonePe-style "view what you've verified" screens). Same backend
  /// endpoint as getKycStatus() -- just parses the richer response.
  Future<KycDetailsResult> getKycDetails() async {
    try {
      final res = await _dio.get('/v1/user/kyc/status');
      final data = ApiService.unwrap(res);
      return KycDetailsResult.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }
  /// Registers/refreshes this device's FCM token -- lets the backend push
  /// a notification straight to this device when a recharge confirms
  /// after the app has been closed (see PushNotificationService.kt).
  Future<void> updateFcmToken(String token) async {
    try {
      await _dio.put('/v1/user/fcm-token', data: {'token': token});
    } on DioException catch (e) {
      debugPrint('updateFcmToken failed (non-fatal): ${e.message}');
    }
  }
}