import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_card.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.paddingPage),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              // Logo
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: AppColors.primaryGlow, blurRadius: 24)],
                      ),
                      child: Center(
                        child: Text('Y',
                            style: AppTextStyles.displaySmall.copyWith(
                                color: AppColors.backgroundPrimary, fontSize: 36)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('YouPI',
                        style: AppTextStyles.displaySmall.copyWith(color: AppColors.primary)),
                    const SizedBox(height: 4),
                    Text(AppStrings.splashPowered,
                        style: AppTextStyles.captionText,
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Text(
                AppStrings.welcomeHeadline,
                style: AppTextStyles.headlineLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [Colors.transparent, AppColors.primary, Colors.transparent]),
                ),
              ),
              const SizedBox(height: 24),
              // Register card
              YoupiCard(
                onTap: () => context.push('/onboarding/carousel'),  // Bug #7: show intro carousel first
                showGlow: false,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.person_add_rounded, color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AppStrings.welcomeRegisterTitle, style: AppTextStyles.headlineSmall),
                          Text(AppStrings.welcomeRegisterSubtitle, style: AppTextStyles.bodySmall),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Login card
              YoupiCard(
                onTap: () => context.push('/auth/mobile'),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundSurface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.login_rounded, color: AppColors.textSecondary, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(AppStrings.welcomeLoginTitle, style: AppTextStyles.headlineSmall),
                          Text(AppStrings.welcomeLoginSubtitle, style: AppTextStyles.bodySmall),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Feature chips
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: ['BNPL', 'Gold', 'FD'].map((tag) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Chip(
                    label: Text(tag, style: AppTextStyles.chipText.copyWith(color: AppColors.primary)),
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    side: const BorderSide(color: AppColors.primary, width: 1),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppDimensions.radiusChip),
                    ),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 20),
              YoupiButton(
                label: AppStrings.welcomeGuestBtn,
                type: YoupiButtonType.ghost,
                onPressed: () => context.go('/dashboard/home'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}