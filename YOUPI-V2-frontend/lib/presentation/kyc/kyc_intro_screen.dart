import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';
import 'kyc_viewmodel.dart';

class KycIntroScreen extends StatelessWidget {
  const KycIntroScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => KycViewModel(),
      child: Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(backgroundColor: AppColors.backgroundPrimary),
        body: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingPage),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(AppStrings.kycIntroTitle, style: AppTextStyles.displaySmall),
              const SizedBox(height: 8),
              Text(AppStrings.kycIntroSubtitle,
                  style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              // Feature chips
              Wrap(
                spacing: 8,
                children: ['BNPL Credit', 'Digital Gold', 'Fixed Deposits'].map((t) => Chip(
                  label: Text(t, style: AppTextStyles.chipText.copyWith(color: AppColors.primary)),
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                )).toList(),
              ),
              const SizedBox(height: 24),
              Text("What You'll Need", style: AppTextStyles.headlineSmall),
              const SizedBox(height: 12),
              ...['Aadhaar number + OTP', 'PAN card number', 'Live selfie photo'].map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 18),
                  const SizedBox(width: 10),
                  Text(s, style: AppTextStyles.bodyMedium),
                ]),
              )),
              const SizedBox(height: 20),
              // Warning banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.warning.withOpacity(0.4)),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_rounded, color: AppColors.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(AppStrings.kycLockedBanner,
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.warning))),
                ]),
              ),
              const Spacer(),
              Row(
                children: [
                  const Icon(Icons.lock_rounded, color: AppColors.textSecondary, size: 14),
                  const SizedBox(width: 6),
                  Text(AppStrings.kycEncryption, style: AppTextStyles.captionText),
                ],
              ),
              const SizedBox(height: 12),
              YoupiButton(
                label: AppStrings.kycStartBtn,
                onPressed: () => context.push('/kyc/aadhaar'),
              ),
              const SizedBox(height: 10),
              YoupiButton(
                label: AppStrings.kycSkipBtn,
                type: YoupiButtonType.ghost,
                onPressed: () => context.go('/dashboard/home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
