import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';

class BnplApplyStep3Screen extends StatelessWidget {
  const BnplApplyStep3Screen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(backgroundColor: AppColors.backgroundPrimary, title: const Text('Apply for BNPL')),
      body: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: 1.0,
                backgroundColor: AppColors.divider, valueColor: const AlwaysStoppedAnimation(AppColors.primary)),
            const SizedBox(height: 8),
            Text('Step 3 of 3 • Review & Submit', style: AppTextStyles.labelMedium),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.backgroundCard,
                borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(children: [
                _SummaryRow('Application Type', 'BNPL Credit Line'),
                const Divider(color: AppColors.divider, height: 20),
                _SummaryRow('Max Limit Applied', '₹5,000'),
                const Divider(color: AppColors.divider, height: 20),
                _SummaryRow('Processing Fee', 'None'),
                const Divider(color: AppColors.divider, height: 20),
                _SummaryRow('Approval Time', '~2 min'),
              ]),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.warning.withOpacity(0.4)),
              ),
              child: const Row(children: [
                Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 18),
                SizedBox(width: 8),
                Expanded(child: Text('This is a soft credit check and will not affect your CIBIL score.',
                    style: TextStyle(color: AppColors.warning, fontSize: 12))),
              ]),
            ),
            const Spacer(),
            YoupiButton(
              label: 'Submit Application',
              onPressed: () => context.go('/bnpl/approved'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow(this.label, this.value);
  @override Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: AppTextStyles.bodyMedium),
      Text(value, style: AppTextStyles.labelLarge),
    ],
  );
}
