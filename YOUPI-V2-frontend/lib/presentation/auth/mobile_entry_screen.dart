import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_input.dart';
import 'auth_viewmodel.dart';

class MobileEntryScreen extends StatelessWidget {
  const MobileEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<AuthViewModel>();
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(backgroundColor: AppColors.backgroundPrimary, elevation: 0),
      body: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(AppStrings.mobileTitle, style: AppTextStyles.displaySmall),
            const SizedBox(height: 8),
            Text(AppStrings.mobileSubtitle,
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 32),
            // Mobile input row
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
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: vm.setMobile,
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
            const Spacer(),
            // Security badge
            Row(
              children: [
                const Icon(Icons.lock_rounded, color: AppColors.primary, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(AppStrings.bankGradeSecurity,
                      style: AppTextStyles.captionText),
                ),
              ],
            ),
            const SizedBox(height: 16),
            YoupiButton(
              label: AppStrings.sendOtp,
              isLoading: vm.isLoading,
              onPressed: vm.isMobileValid
                  ? () async {
                // BUG FIX: this screen is reached ONLY via "New User?
                // Register" (Welcome -> onboarding carousel -> here) --
                // "Existing User? Login" on Welcome already goes straight
                // to /auth/login-mpin and never touches this screen at
                // all. A previous session's MPIN-first-login fix was
                // wrongly applied here too, making this button push
                // /auth/login-mpin -- which skips straight to an MPIN
                // PAD (LoginMpinScreen sees a handed-in mobile and jumps
                // to step 1) for ANY number typed here, including a
                // genuinely brand-new user who has never set an MPIN.
                // They'd have to type a meaningless 4-digit guess, get
                // rejected (USER_NOT_FOUND/MPIN_NOT_SET), and only THEN
                // fall back to OTP -- instead of the correct
                // number -> OTP -> name/DOB/email -> set MPIN flow.
                //
                // OtpVerifyScreen already contains the correct new-vs-
                // existing routing after verification (isNewUser ->
                // /auth/profile-setup; existing/recovery -> mpin-setup
                // with isReset: true) -- this screen just needs to
                // actually send the OTP and get out of the way.
                final ok = await vm.sendOtp();
                if (!context.mounted) return;
                if (ok) {
                  context.push('/auth/otp', extra: {'mobile': vm.mobile, 'isRecovery': false});
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(vm.error ?? 'Could not send OTP. Please try again.'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                }
              }
                  : null,
            ),
            const SizedBox(height: 16),
            Center(
              child: TextButton(
                onPressed: () {},
                child: Text(AppStrings.termsLink,
                    style: AppTextStyles.tealLink),
              ),
            ),
          ],
        ),
      ),
    );
  }
}