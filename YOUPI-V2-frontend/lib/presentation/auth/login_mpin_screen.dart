import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/services/storage_service.dart';
import '../../core/widgets/youpi_button.dart';
import '../../data/repositories/auth_repository.dart';
import 'auth_viewmodel.dart';

/// "Existing User? Login" flow, reached from the Welcome screen.
///
/// Normal case (this device has logged in before): skips straight to the
///   MPIN pad using the remembered mobile number -- no retyping needed.
/// First time on this device (nothing remembered yet): shows the mobile
///   step first, same as before.
/// Recovery case (5 wrong MPIN attempts, or "Forgot MPIN?" tapped): drops
///   back to the mobile step so the number can be confirmed/corrected, then
///   goes straight to OTP -- it does NOT return to the MPIN pad, since the
///   whole point of recovery is that MPIN can't be trusted right now.
///
/// On success -> straight to dashboard with the real account (no OTP wait).
/// On wrong MPIN -> shows the server's actual attempts-remaining count and
///   lets the user retry, right here.
/// On lockout / MPIN never set / mobile not registered / untrusted device
///   -> falls back to the OTP flow to re-establish identity (existing
///   OtpVerifyScreen already knows how to route a brand-new vs an existing
///   user correctly).
class LoginMpinScreen extends StatefulWidget {
  const LoginMpinScreen({super.key});

  @override
  State<LoginMpinScreen> createState() => _LoginMpinScreenState();
}

class _LoginMpinScreenState extends State<LoginMpinScreen> {
  final AuthRepository _authRepo = AuthRepository();

  int _step = 0; // 0 = mobile entry, 1 = MPIN pad
  // True once the mobile step is being shown as part of OTP-recovery rather
  // than first-time entry -- changes what the "Continue" button on that step
  // does (send OTP directly, instead of moving on to the MPIN pad).
  bool _recoveryMode = false;
  bool _checkingRememberedMobile = true;
  String _mobile = '';
  String _mpin = '';
  bool _isVerifying = false;
  bool _isSendingOtp = false;
  String? _errorText;

  bool get _isMobileValid => _mobile.length == 10;

  @override
  void initState() {
    super.initState();
    _loadRememberedMobile();
  }

  Future<void> _loadRememberedMobile() async {
    final saved = await StorageService.getLastMobile();
    if (!mounted) return;
    if (saved != null && saved.length == 10) {
      setState(() {
        _mobile = saved;
        _step = 1; // skip straight to the MPIN pad
        _checkingRememberedMobile = false;
      });
    } else {
      setState(() => _checkingRememberedMobile = false);
    }
  }

  void _goToMpinStep() {
    if (!_isMobileValid) return;

    if (_recoveryMode) {
      // Recovery path -- don't show the MPIN pad again, go straight to OTP.
      _fallBackToOtp(null);
      return;
    }

    setState(() {
      _step = 1;
      _mpin = '';
      _errorText = null;
    });
  }

  /// Entered on 5 wrong MPIN attempts (server-side lockout), an untrusted
  /// device, an unset MPIN, an unrecognised mobile, or a manual "Forgot
  /// MPIN?" tap. Drops back to the mobile step (pre-filled, editable) so the
  /// number can be confirmed before OTP goes out.
  void _enterRecoveryMode({String? message}) {
    if (message != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: AppColors.error),
      );
    }
    setState(() {
      _recoveryMode = true;
      _step = 0;
      _mpin = '';
      _errorText = null;
    });
  }

  void _onDigit(String d) {
    if (_isVerifying || _mpin.length >= 4) return;
    setState(() {
      _mpin += d;
      _errorText = null;
    });
    if (_mpin.length == 4) _verify();
  }

  void _onDelete() {
    if (_isVerifying || _mpin.isEmpty) return;
    setState(() => _mpin = _mpin.substring(0, _mpin.length - 1));
  }

  Future<void> _verify() async {
    setState(() => _isVerifying = true);

    final result = await _authRepo.loginWithMpin(_mobile, _mpin);

    if (!mounted) return;

    if (result.success) {
      if (result.isNewUser || !result.profileComplete) {
        // Shouldn't normally happen on this path (MPIN only exists once
        // profile+MPIN setup is done) -- but handle it safely just in case.
        context.go('/auth/profile-setup');
      } else {
        context.go('/dashboard/home');
      }
      return;
    }

    if (result.errorCode == 'USER_INACTIVE') {
      setState(() {
        _isVerifying = false;
        _mpin = '';
      });
      _showBlockingDialog(
        'Account Inactive',
        result.message ?? 'This account is inactive. Please contact support.',
      );
      return;
    }

    if (result.shouldFallBackToOtp) {
      setState(() => _isVerifying = false);
      _enterRecoveryMode(
        message: result.message ?? "Let's verify your number again via OTP.",
      );
      return;
    }

    // MPIN_INVALID (wrong PIN, attempts remain) or an unknown/network error
    // -- either way, let them retry right here.
    setState(() {
      _isVerifying = false;
      _mpin = '';
      _errorText = result.attemptsRemaining != null
          ? 'Wrong MPIN. ${result.attemptsRemaining} attempt(s) left.'
          : (result.message ?? 'Something went wrong. Please try again.');
    });
  }

  Future<void> _fallBackToOtp(String? reason) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(reason ?? "Let's verify your number again via OTP."),
        backgroundColor: AppColors.error,
      ),
    );

    setState(() => _isSendingOtp = true);
    final vm = context.read<AuthViewModel>();
    vm.setMobile(_mobile);
    final ok = await vm.sendOtp();
    if (!mounted) return;
    setState(() => _isSendingOtp = false);

    if (ok) {
      context.push('/auth/otp', extra: _mobile);
    } else {
      _showBlockingDialog(
        'Could not send OTP',
        vm.error ?? 'Please check your connection and try again.',
      );
    }
  }

  void _showBlockingDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundCard,
        title: Text(title, style: AppTextStyles.headlineSmall),
        content: Text(message,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('OK', style: AppTextStyles.tealLink),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingRememberedMobile) {
      return const Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    // Only let the system/hardware back button actually leave this screen
    // (pop the route) when we're on the first, non-recovery mobile step --
    // otherwise it should step back through MPIN pad -> mobile step ->
    // recovery-back-to-MPIN, exactly like the AppBar arrow below.
    final canPop = _step == 0 && !_recoveryMode;

    return PopScope(
      canPop: canPop,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(
          backgroundColor: AppColors.backgroundPrimary,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () {
              if (canPop) {
                context.pop();
              } else {
                _handleBack();
              }
            },
          ),
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(AppDimensions.paddingPage),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - (AppDimensions.paddingPage * 2),
                  ),
                  child: _step == 0 ? _buildMobileStep() : _buildMpinStep(),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // Shared by both the AppBar arrow and the phone's hardware back button, so
  // they always behave identically.
  void _handleBack() {
    if (_step == 1) {
      setState(() {
        _step = 0;
        _mpin = '';
        _errorText = null;
      });
    } else if (_recoveryMode) {
      // Back out of recovery -- return to the MPIN pad rather than leaving
      // the screen entirely, in case the lockout/forgot tap was accidental
      // and the account still has attempts left.
      setState(() {
        _recoveryMode = false;
        _step = 1;
        _errorText = null;
      });
    }
  }

  Widget _buildMobileStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_recoveryMode ? 'Confirm your number' : 'Welcome back',
            style: AppTextStyles.displaySmall),
        const SizedBox(height: 8),
        Text(
            _recoveryMode
                ? "We'll send an OTP to verify it's really you."
                : 'Enter your registered mobile number',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 32),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                color: AppColors.backgroundCard,
                borderRadius: BorderRadius.circular(AppDimensions.radiusInput),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  const Text('🇮🇳', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 6),
                  Text('+91', style: AppTextStyles.inputValue),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                key: ValueKey('mobile_field_$_recoveryMode'),
                initialValue: _mobile,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged: (v) => setState(() => _mobile = v.trim()),
                style: AppTextStyles.inputValue,
                decoration: InputDecoration(
                  hintText: '10-digit mobile',
                  counterText: '',
                  filled: true,
                  fillColor: AppColors.backgroundCard,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusInput),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusInput),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusInput),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 40),
        YoupiButton(
          label: _recoveryMode ? 'Send OTP' : 'Continue',
          onPressed: _isMobileValid ? _goToMpinStep : null,
        ),
      ],
    );
  }

  Widget _buildMpinStep() {
    return Column(
      children: [
        const SizedBox(height: 20),
        Text('Enter MPIN', style: AppTextStyles.displaySmall, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('For +91 ×××××${_mobile.substring(_mobile.length - 2)}',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center),
        const SizedBox(height: 40),
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
                  color: i < _mpin.length ? AppColors.primary : AppColors.divider,
                  boxShadow: i < _mpin.length
                      ? [BoxShadow(color: AppColors.primaryGlow, blurRadius: 8)]
                      : null,
                ),
              )),
        ),
        const SizedBox(height: 16),
        if (_isVerifying || _isSendingOtp)
          const CircularProgressIndicator(color: AppColors.primary),
        if (_errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_errorText!, style: AppTextStyles.errorText, textAlign: TextAlign.center),
          ),
        const SizedBox(height: 32),
        for (final row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['', '0', '⌫']
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((d) {
              return GestureDetector(
                onTap: () {
                  if (d == '⌫') {
                    _onDelete();
                  } else if (d.isNotEmpty) {
                    _onDigit(d);
                  }
                },
                child: Container(
                  width: 80,
                  height: 72,
                  margin: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: d.isEmpty ? Colors.transparent : AppColors.backgroundCard,
                    borderRadius: BorderRadius.circular(12),
                    border: d.isEmpty ? null : Border.all(color: AppColors.divider),
                  ),
                  child: Center(
                    child: d == '⌫'
                        ? const Icon(Icons.backspace_rounded,
                        color: AppColors.textSecondary, size: 20)
                        : Text(d, style: AppTextStyles.headlineLarge),
                  ),
                ),
              );
            }).toList(),
          ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: (_isVerifying || _isSendingOtp)
              ? null
              : () => _enterRecoveryMode(),
          child: Text('Forgot MPIN? Use OTP instead', style: AppTextStyles.tealLink),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}