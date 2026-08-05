import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';

class BnplNotApprovedScreen extends StatelessWidget {
  const BnplNotApprovedScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        // BUG FIX: same Column+Spacer overflow issue as mpin_entry_screen.dart
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppDimensions.paddingPage),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - (AppDimensions.paddingPage * 2),
                ),
                child: IntrinsicHeight(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Spacer(),
                      Center(
                        child: Container(
                          width: 100, height: 100,
                          decoration: BoxDecoration(
                            color: AppColors.error.withOpacity(0.1),
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.error, width: 3),
                          ),
                          child: const Icon(Icons.close_rounded, color: AppColors.error, size: 50),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text('Not Approved Yet',
                          style: AppTextStyles.displaySmall, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text('We couldn\'t approve your BNPL application at this time.',
                          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                      Text('You can try:', style: AppTextStyles.headlineSmall),
                      const SizedBox(height: 12),
                      for (final tip in [
                        'SmartDeposit — Use your own funds',
                        'Complete KYC to improve eligibility',
                        'Try again after 30 days',
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            const Icon(Icons.arrow_right_rounded, color: AppColors.primary),
                            const SizedBox(width: 4),
                            Text(tip, style: AppTextStyles.bodyMedium),
                          ]),
                        ),
                      const Spacer(),
                      YoupiButton(
                        label: 'Try SmartDeposit',
                        onPressed: () => context.push('/bnpl/smart-deposit'),
                      ),
                      const SizedBox(height: 10),
                      YoupiButton(
                        label: 'Back to Home',
                        type: YoupiButtonType.ghost,
                        onPressed: () => context.go('/dashboard/home'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}