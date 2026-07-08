import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_input.dart';

// ─────────── Step 2 ───────────
class LoanApplyStep2Screen extends StatelessWidget {
  const LoanApplyStep2Screen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(title: const Text('Personal Loan'), backgroundColor: AppColors.backgroundPrimary),
      body: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LinearProgressIndicator(value: 2 / 3, backgroundColor: AppColors.divider, valueColor: const AlwaysStoppedAnimation(AppColors.primary)),
          const SizedBox(height: 8),
          Text('Step 2 of 3 • Personal & Employment Info', style: AppTextStyles.labelMedium),
          const SizedBox(height: 24),
          const YoupiInput(label: 'Monthly Income', hint: '₹35,000', keyboardType: TextInputType.number),
          const SizedBox(height: 16),
          const YoupiInput(label: 'Employer / Business Name', hint: 'e.g. Infosys'),
          const SizedBox(height: 16),
          const YoupiInput(label: 'Bank Account Number', hint: 'XXXXXXXXXXXXXXXX'),
          const Spacer(),
          YoupiButton(label: 'Next', onPressed: () => context.push('/loan/apply/step3')),
        ]),
      ),
    );
  }
}
