import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';

class LoanApprovedScreen extends StatelessWidget {
  const LoanApprovedScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Spacer(),
            Center(
              child: Container(
                width: 120, height: 120,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1), shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary, width: 3),
                  boxShadow: [BoxShadow(color: AppColors.primaryGlow, blurRadius: 30, spreadRadius: 8)]),
                child: const Icon(Icons.check_rounded, color: AppColors.primary, size: 60),
              ),
            ),
            const SizedBox(height: 24),
            Text('Loan Approved! 🎉', style: AppTextStyles.displaySmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('₹1,00,000 will be credited within 2 hours.',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary), textAlign: TextAlign.center),
            const Spacer(),
            YoupiButton(label: 'View My Loans', onPressed: () => context.go('/loan/my-loans')),
            const SizedBox(height: 10),
            YoupiButton(label: 'Go to Home', type: YoupiButtonType.ghost, onPressed: () => context.go('/dashboard/home')),
          ]),
        ),
      ),
    );
  }
}
