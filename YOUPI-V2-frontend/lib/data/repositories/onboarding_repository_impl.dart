import 'package:dio/dio.dart';

import '../../presentation/onboarding/onboarding_questions_screen.dart'
    show OnboardingAnswers, OnboardingRepository;
// TODO: adjust this import to wherever your shared Dio/ApiClient wrapper lives,
// e.g. import '../network/api_client.dart';
// This file assumes a class exposing a configured `Dio` instance whose
// baseOptions already include the base URL and the Firebase JWT auth
// interceptor (same client used by RechargeService/WalletService calls).

class OnboardingRepositoryImpl implements OnboardingRepository {
  final Dio _dio;

  OnboardingRepositoryImpl(this._dio);

  @override
  Future<void> submit(OnboardingAnswers answers) async {
    try {
      await _dio.post(
        '/v1/onboarding/answers',
        data: answers.toJson(),
      );
    } on DioException catch (e) {
      // Surface a clean error to the screen; it already shows a SnackBar
      // and lets the user retry via the same Continue button.
      final message = e.response?.data is Map
          ? (e.response?.data['message'] ?? e.message)
          : e.message;
      throw Exception('Onboarding submit failed: $message');
    }
  }

  /// Optional: used if you want to prefill/resume onboarding for a user
  /// who partially completed it before (e.g. app was closed mid-flow).
  Future<Map<String, dynamic>> fetchExisting() async {
    try {
      final response = await _dio.get('/v1/onboarding/answers');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw Exception('Failed to load existing onboarding answers: ${e.message}');
    }
  }
}