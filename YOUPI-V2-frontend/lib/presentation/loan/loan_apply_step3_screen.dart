import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';

class LoanApplyStep3Screen extends StatelessWidget {
  const LoanApplyStep3Screen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(title: const Text('Personal Loan'), backgroundColor: AppColors.backgroundPrimary),
      body: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: 1.0, backgroundColor: AppColors.divider,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary)),
            const SizedBox(height: 8),
            Text('Step 3 of 3 • Review', style: AppTextStyles.labelMedium),
            const SizedBox(height: 24),
            YoupiButton(label: 'Submit Application', onPressed: () => context.go('/loan/approved')),
          ],
        ),
      ),
    );
  }
}
