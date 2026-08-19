import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_input.dart';
import 'kyc_viewmodel.dart';

class PanVerifyScreen extends StatelessWidget {
  const PanVerifyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<KycViewModel>();
    final ctx = context;
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(backgroundColor: AppColors.backgroundPrimary),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Now 3 of 4 steps in this route sequence (was 3 of 3) --
            // Bank Account verification is a new step after this one.
            LinearProgressIndicator(value: 3 / 4, backgroundColor: AppColors.divider,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary)),
            const SizedBox(height: 8),
            Text('Step 3 of 4', style: AppTextStyles.labelMedium),
            const SizedBox(height: 24),
            Text(AppStrings.panTitle, style: AppTextStyles.displaySmall),
            const SizedBox(height: 24),
            YoupiInput(
              label: 'PAN Number',
              hint: 'ABCDE1234F',
              maxLength: 10,
              onChanged: (v) => vm.setPan(v.toUpperCase()),
            ),
            const SizedBox(height: 12),
            YoupiButton(
              label: vm.panVerified ? 'Verified ✓' : 'Verify PAN',
              isLoading: vm.isLoading,
              onPressed: (vm.isPanFormatValid && !vm.panVerified)
                  ? () => vm.verifyPanWithBackend()
                  : null,
            ),
            if (vm.panVerified)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.success.withOpacity(0.4)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        vm.panHolderName != null
                            ? 'PAN verified — ${vm.panHolderName}'
                            : 'PAN details verified',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.success),
                      ),
                    ),
                  ]),
                ),
              ),
            if (vm.panError != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(vm.panError!,
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
              ),
            const SizedBox(height: 24),
            Text('Selfie Verification', style: AppTextStyles.headlineSmall),
            const SizedBox(height: 16),
            Center(
              child: GestureDetector(
                onTap: vm.captureSelfie,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: vm.selfieCapture ? AppColors.success : AppColors.primary,
                      width: 2,
                    ),
                    color: AppColors.backgroundCard,
                  ),
                  child: Center(
                    child: vm.selfieCapture
                        ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 48),
                      Text('Selfie Captured', style: AppTextStyles.labelMedium.copyWith(color: AppColors.success)),
                    ])
                        : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.camera_alt_rounded, color: AppColors.primary, size: 40),
                      const SizedBox(height: 8),
                      Text('Open Camera', style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary)),
                    ]),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text('Well lit room • Face visible • No hats/sunglasses',
                style: AppTextStyles.captionText, textAlign: TextAlign.center),
            const SizedBox(height: 32),
            YoupiButton(
              label: 'Continue',
              // CHANGED: was AppStrings.completeKyc + vm.completeKyc() +
              // navigate straight to /kyc/success. Now goes to the new
              // Bank Account verification step instead -- completeKyc()
              // moved to the end of that screen.
              onPressed: (vm.panVerified && vm.selfieCapture)
                  ? () => ctx.push('/kyc/bank-account')
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}