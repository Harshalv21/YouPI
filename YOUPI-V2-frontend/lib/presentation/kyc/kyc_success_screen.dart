import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';

class KycSuccessScreen extends StatelessWidget {
  const KycSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingPage),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 800),
                  builder: (ctx, v, _) => Transform.scale(
                    scale: v,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primary, width: 3),
                        boxShadow: [BoxShadow(color: AppColors.primaryGlow, blurRadius: 30, spreadRadius: 5)],
                      ),
                      child: const Icon(Icons.check_rounded, color: AppColors.primary, size: 60),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(AppStrings.kycSuccessTitle, style: AppTextStyles.displayMedium, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(AppStrings.kycSuccessSubtitle,
                  style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center),
              const SizedBox(height: 32),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: ['BNPL', 'Digital Gold', 'Fixed Deposits', 'Wallet'].map((f) => Chip(
                  label: Text(f, style: AppTextStyles.chipText.copyWith(color: AppColors.primary)),
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                )).toList(),
              ),
              const Spacer(),
              YoupiButton(
                label: AppStrings.goToDashboard,
                onPressed: () => context.go('/dashboard/home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
