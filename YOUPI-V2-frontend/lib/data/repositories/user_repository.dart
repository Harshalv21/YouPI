// lib/data/repositories/user_repository.dart
//
// Real backend-connected user repository.
// Endpoints (Bearer token auto-added by ApiService):
//   GET /v1/user/profile        -> profile
//   PUT /v1/user/profile        -> update name/email/dob
//   GET /v1/user/kyc/status     -> KYC status

import 'package:dio/dio.dart';
import '../../core/services/api_service.dart';
import '../models/user_model.dart';
import 'package:flutter/foundation.dart';

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
      // Response may be { status: "VERIFIED" } or { kycStatus: "..." } or a bool.
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
}