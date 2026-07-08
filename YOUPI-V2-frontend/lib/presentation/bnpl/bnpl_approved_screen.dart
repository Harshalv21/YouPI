import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';

class BnplApprovedScreen extends StatelessWidget {
  const BnplApprovedScreen({super.key});
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
                  builder: (ctx, v, _) => Transform.scale(scale: v,
                    child: Container(
                      width: 120, height: 120,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primary, width: 3),
                        boxShadow: [BoxShadow(color: AppColors.primaryGlow, blurRadius: 30, spreadRadius: 8)],
                      ),
                      child: const Icon(Icons.check_rounded, color: AppColors.primary, size: 60),
                    )),
                ),
              ),
              const SizedBox(height: 28),
              Text('BNPL Approved! 🎉', style: AppTextStyles.displaySmall, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('Your ₹5,000 credit line is now active.',
                  style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.backgroundCard, const Color(0xFF1A2030)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
                  border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                ),
                child: Column(children: [
                  const Text('•••• •••• •••• 8824', style: TextStyle(fontSize: 20, letterSpacing: 4, color: AppColors.textPrimary, fontFamily: 'monospace')),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Text('Available: ₹5,000', style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
                    Text('BNPL', style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
                  ]),
                ]),
              ),
              const Spacer(),
              YoupiButton(label: 'Start Shopping', onPressed: () => context.go('/dashboard/home')),
              const SizedBox(height: 10),
              YoupiButton(
                label: 'Enable SmartDeposit',
                type: YoupiButtonType.secondary,
                onPressed: () => context.push('/bnpl/smart-deposit'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

