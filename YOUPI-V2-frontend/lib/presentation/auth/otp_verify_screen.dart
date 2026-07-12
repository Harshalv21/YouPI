import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/otp_input_field.dart';
import '../../core/widgets/youpi_button.dart';
import 'auth_viewmodel.dart';

class OtpVerifyScreen extends StatefulWidget {
  final String mobile;
  const OtpVerifyScreen({super.key, required this.mobile});

  @override
  State<OtpVerifyScreen> createState() => _OtpVerifyScreenState();
}

class _OtpVerifyScreenState extends State<OtpVerifyScreen> {
  String _otp = '';   // ab yahan — rebuild pe reset nahi hoga

  // Bumped every time OTP is resent. Used as the OtpInputField's key so the
  // PIN boxes (and Firebase's underlying verification session) are always
  // in sync -- otherwise a stale, already-superseded code can sit visible
  // in the boxes and get submitted against the *new* session, which Firebase
  // correctly rejects as invalid-verification-code even though the digits
  // shown on screen look right.
  int _resendGeneration = 0;

  Future<void> _handleResend() async {
    setState(() {
      _otp = '';
      _resendGeneration++;
    });
    await context.read<AuthViewModel>().resendOtp();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();   // shared vm (root se)
    final mobile = widget.mobile;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(backgroundColor: AppColors.backgroundPrimary),
      body: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(AppStrings.otpTitle, style: AppTextStyles.displaySmall),
            const SizedBox(height: 8),
            Text(
              'OTP sent to +91 ×××××${mobile.length >= 2 ? mobile.substring(mobile.length - 2) : "64"}',
              style: AppTextStyles.bodyMedium
                  .copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.pop(),
              child: Text(AppStrings.changeNumber,
                  style: AppTextStyles.tealLink),
            ),
            const SizedBox(height: 32),
            OtpInputField(
              key: ValueKey(_resendGeneration),
              onChanged: (val) {
                _otp = val;
              },
              onCompleted: (val) {
                _otp = val;
              },
            ),
            const SizedBox(height: 24),
            // Resend timer
            Center(
              child: vm.otpResendCountdown > 0
                  ? Text(
                'Resend OTP in 00:${vm.otpResendCountdown.toString().padLeft(2, '0')}',
                style: AppTextStyles.bodySmall,
              )
                  : TextButton(
                onPressed: _handleResend,
                child: Text(AppStrings.resendOtp,
                    style: AppTextStyles.tealLink),
              ),
            ),
            const Spacer(),
            if (vm.error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(vm.error!,
                    style: AppTextStyles.errorText,
                    textAlign: TextAlign.center),
              ),
            YoupiButton(
              label: AppStrings.verifyAndContinue,
              isLoading: vm.isLoading,
              onPressed: () async {
                final result = await vm.verifyOtp(_otp);
                if (result != null && context.mounted) {
                  final isNew = result['isNewUser'] == true;
                  final profileDone = result['profileComplete'] == true;

                  if (isNew || !profileDone) {
                    context.go('/auth/profile-setup');
                  } else {
                    // Reaching here as an *existing* user with a complete
                    // profile only happens now via the MPIN-recovery path
                    // (LoginMpinScreen falls back to OTP after 5 wrong
                    // attempts, an unset MPIN, or an unrecognised mobile).
                    // So instead of going straight to the dashboard, make
                    // them set a new MPIN first -- that's the whole point
                    // of this recovery step.
                    context.go('/auth/mpin-setup', extra: {'isReset': true});
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}