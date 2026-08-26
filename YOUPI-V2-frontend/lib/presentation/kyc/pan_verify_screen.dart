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
    // BUG FIX (back button exits app): same root cause as kyc_intro_screen.dart
    // -- if this screen ends up at the top of the nav stack with nothing left
    // to pop, Android's back button would close the app instead of navigating.
    // PopScope intercepts that and sends the user to the dashboard instead.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          context.go('/dashboard/home');
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar( backgroundColor: AppColors.backgroundPrimary,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: () => ctx.push('/kyc/bank-account'),
                child: Text('Skip',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
              ),
            ),
          ],
        ),
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
                // BUG FIX: onTap now actually opens the camera (see
                // KycViewModel.captureSelfie) instead of just flipping a flag
                // with nothing happening on screen.
                child: GestureDetector(
                  onTap: vm.isLoading
                      ? null
                      : () async {
                    await vm.captureSelfie();
                  },
                  child: Container(
                    width: 160,
                    height: 160,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: vm.selfieCapture ? AppColors.success : AppColors.primary,
                        width: 2,
                      ),
                      color: AppColors.backgroundCard,
                      image: vm.selfieCapture && vm.selfiePhoto != null
                          ? DecorationImage(image: FileImage(vm.selfiePhoto!), fit: BoxFit.cover)
                          : null,
                    ),
                    child: (vm.selfieCapture && vm.selfiePhoto != null)
                        ? Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: double.infinity,
                        color: Colors.black.withOpacity(0.45),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 22),
                      ),
                    )
                        : Center(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.camera_alt_rounded, color: AppColors.primary, size: 40),
                        const SizedBox(height: 8),
                        Text('Open Camera', style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary)),
                      ]),
                    ),
                  ),
                ),
              ),
              if (vm.selfieCapture)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Center(
                    child: TextButton(
                      onPressed: vm.retakeSelfie,
                      child: Text('Retake photo', style: AppTextStyles.tealLink),
                    ),
                  ),
                ),
              if (vm.selfieError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(vm.selfieError!,
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
                      textAlign: TextAlign.center),
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
      ),
    );
  }
}