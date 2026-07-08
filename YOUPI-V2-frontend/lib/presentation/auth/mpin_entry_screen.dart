// TODO Implement this library.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/services/storage_service.dart';

/// App-open lock screen. Shown on every launch when the user is logged in
/// and has an MPIN set. Verifies against the locally stored MPIN hash.
///
/// On success → /dashboard/home.
/// After 5 wrong attempts → temporarily blocks input.
class MpinEntryScreen extends StatefulWidget {
  const MpinEntryScreen({super.key});

  @override
  State<MpinEntryScreen> createState() => _MpinEntryScreenState();
}

class _MpinEntryScreenState extends State<MpinEntryScreen> {
  static const int _maxAttempts = 5;

  final LocalAuthentication _localAuth = LocalAuthentication();

  String _mpin = '';
  int _attempts = 0;
  bool _isLocked = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    // If biometric is enabled, offer it right away.
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
  }

  Future<void> _tryBiometric() async {
    final enabled = await StorageService.isBiometricEnabled();
    if (!enabled) return;
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) return;
      final ok = await _localAuth.authenticate(
        localizedReason: 'Unlock YOUPI',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (ok && mounted) {
        context.go('/dashboard/home');
      }
    } catch (_) {
      // Biometric failed/cancelled → user can still enter MPIN.
    }
  }

  void _onDigit(String d) {
    if (_isLocked || _checking) return;
    if (_mpin.length >= 4) return;
    setState(() {
      _mpin += d;
      if (_mpin.length == 4) _verify();
    });
  }

  void _onDelete() {
    if (_isLocked || _checking) return;
    if (_mpin.isEmpty) return;
    setState(() => _mpin = _mpin.substring(0, _mpin.length - 1));
  }

  Future<void> _verify() async {
    setState(() => _checking = true);
    final ok = await StorageService.verifyMpin(_mpin);

    if (ok) {
      if (mounted) context.go('/dashboard/home');
      return;
    }

    // Wrong MPIN
    _attempts++;
    setState(() {
      _mpin = '';
      _checking = false;
    });

    if (_attempts >= _maxAttempts) {
      setState(() => _isLocked = true);
      _showError(
          'Too many wrong attempts. Please sign in again with OTP.');
      // Force re-login: clear session and send to welcome.
      await StorageService.clearAll();
      if (mounted) context.go('/onboarding/welcome');
      return;
    }

    _showError(
        'Wrong MPIN. ${_maxAttempts - _attempts} attempt(s) left.');
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  Future<void> _forgotMpin() async {
    // Forgot MPIN → re-authenticate via OTP. Clear session, go to login.
    await StorageService.clearAll();
    if (mounted) context.go('/auth/mobile');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingPage),
          child: Column(
            children: [
              const SizedBox(height: 40),
              // Lock icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary),
                ),
                child: const Icon(Icons.lock_rounded,
                    color: AppColors.primary, size: 30),
              ),
              const SizedBox(height: 20),
              Text('Enter MPIN',
                  style: AppTextStyles.displaySmall,
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('Enter your 4-digit MPIN to continue',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center),
              const SizedBox(height: 40),
              // Dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                    4,
                        (i) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < _mpin.length
                            ? AppColors.primary
                            : AppColors.divider,
                        boxShadow: i < _mpin.length
                            ? [
                          BoxShadow(
                              color: AppColors.primaryGlow,
                              blurRadius: 8)
                        ]
                            : null,
                      ),
                    )),
              ),
              const SizedBox(height: 16),
              if (_checking)
                const CircularProgressIndicator(color: AppColors.primary),
              const Spacer(),
              // Number pad
              for (final row in [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
                ['⌾', '0', '⌫']
              ])
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: row.map((d) {
                    return GestureDetector(
                      onTap: () {
                        if (d == '⌫') {
                          _onDelete();
                        } else if (d == '⌾') {
                          _tryBiometric();
                        } else {
                          _onDigit(d);
                        }
                      },
                      child: Container(
                        width: 80,
                        height: 72,
                        margin: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: d == '⌾'
                              ? Colors.transparent
                              : AppColors.backgroundCard,
                          borderRadius: BorderRadius.circular(12),
                          border: d == '⌾'
                              ? null
                              : Border.all(color: AppColors.divider),
                        ),
                        child: Center(
                          child: d == '⌫'
                              ? const Icon(Icons.backspace_rounded,
                              color: AppColors.textSecondary, size: 20)
                              : d == '⌾'
                              ? const Icon(Icons.fingerprint_rounded,
                              color: AppColors.primary, size: 26)
                              : Text(d,
                              style: AppTextStyles.headlineLarge),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _forgotMpin,
                child: Text('Forgot MPIN?', style: AppTextStyles.tealLink),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}