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
    await Future.delayed(const Duration(milliseconds: 2000));

    final isFirst = await StorageService.isFirstLaunch();
    if (isFirst) {
      await StorageService.markLaunched();
      return '/onboarding/welcome';
    }

    final hasToken = await StorageService.hasToken();
    if (!hasToken) {
      return '/onboarding/welcome';
    }

    // Logged in. For security, gate the app behind MPIN on every open.
    final hasMpin = await StorageService.hasMpin();
    if (hasMpin) {
      // Send to an MPIN entry screen instead of straight to dashboard.
      return '/auth/mpin-entry';
    }

    // Token but MPIN never set → complete setup.
    return '/auth/mpin-setup';
  }
}