import 'package:flutter/material.dart';
import '../../core/services/storage_service.dart';

class SplashViewModel extends ChangeNotifier {
  bool _isLoading = true;
  bool get isLoading => _isLoading;

  /// Decide where to send the user on app open.
  ///
  /// Rules (fintech-safe):
  /// - First ever launch        → onboarding
  /// - No token                 → onboarding (needs login)
  /// - Token + MPIN set         → MPIN entry (lock screen every open)
  /// - Token but no MPIN yet    → finish MPIN setup
  Future<String> checkAuth() async {
    final results = await Future.wait([
      _resolveRoute(),
      Future.delayed(const Duration(milliseconds: 600)),
    ]);
    return results[0] as String;
  }

  Future<String> _resolveRoute() async {
    final isFirst = await StorageService.isFirstLaunch();
    if (isFirst) {
      await StorageService.markLaunched();
      return '/onboarding/welcome';
    }

    final hasToken = await StorageService.hasToken();
    if (!hasToken) return '/onboarding/welcome';

    final hasMpin = await StorageService.hasMpin();
    return hasMpin ? '/auth/mpin-entry' : '/auth/mpin-setup';
  }
}