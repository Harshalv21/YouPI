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
                final ok = await vm.sendOtp();
                if (ok && context.mounted) {
                  context.push('/auth/otp', extra: vm.mobile);
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