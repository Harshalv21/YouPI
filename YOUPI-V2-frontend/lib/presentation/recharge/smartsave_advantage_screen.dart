import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_card.dart';
import 'recharge_viewmodel.dart';

class SmartSaveAdvantageScreen extends StatelessWidget {
  const SmartSaveAdvantageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(backgroundColor: AppColors.backgroundPrimary,
          title: Text(AppStrings.smartSaveTitle, style: AppTextStyles.headlineMedium)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.secondary, borderRadius: BorderRadius.circular(8)),
                child: Text('SAVE ₹147',
                    style: AppTextStyles.headlineSmall.copyWith(color: AppColors.backgroundPrimary)),
              ),
            ),
            const SizedBox(height: 20),
            Text('YOU ARE SAVING ₹147', style: AppTextStyles.headlineLarge, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            // Comparison
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.backgroundCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.error.withOpacity(0.3)),
                    ),
                    child: Column(children: [
                      Text('Normal way', style: AppTextStyles.bodySmall),
                      const SizedBox(height: 4),
                      Text('₹1,047', style: AppTextStyles.headlineMedium.copyWith(
                          color: AppColors.error, decoration: TextDecoration.lineThrough)),
                    ]),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary),
                    ),
                    child: Column(children: [
                      Text('SmartSave way', style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary)),
                      const SizedBox(height: 4),
                      Text('₹900', style: AppTextStyles.headlineMedium.copyWith(color: AppColors.primary)),
                    ]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Payment Schedule', style: AppTextStyles.headlineSmall),
            const SizedBox(height: 12),
            ...[
              ('1', 'TODAY — INSTANT', '21 Mar 2026', 'Plan activates instantly'),
              ('2', 'Day 28', '18 Apr 2026', 'Auto debit via UPI mandate'),
              ('3', 'Day 56', '16 May 2026', 'Auto debit'),
            ].map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: YoupiCard(
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(s.$1,
                          style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.$2, style: AppTextStyles.labelLarge),
                      Text(s.$3, style: AppTextStyles.captionText),
                      Text(s.$4, style: AppTextStyles.bodySmall),
                    ]),
                  ),
                  Text('₹300', style: AppTextStyles.headlineSmall.copyWith(color: AppColors.primary)),
                ]),
              ),
            )).toList(),
            const SizedBox(height: 20),
            YoupiCard(
              child: Column(children: [
                _Row('Plan Validity', 'Total over 84 days'),
                const Divider(color: AppColors.divider, height: 20),
                _Row('Total', '₹900', valueColor: AppColors.primary),
              ]),
            ),
            const SizedBox(height: 24),
            YoupiButton(
              label: AppStrings.activateSmartSave,
              onPressed: () => context.push('/plans/success'),
            ),
            const SizedBox(height: 12),
            Text('UPI mandate will be set up for auto-debit payments.',
                style: AppTextStyles.captionText, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _Row(this.label, this.value, {this.valueColor});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.bodyMedium),
        Text(value, style: AppTextStyles.labelLarge.copyWith(color: valueColor)),
      ],
    );
  }
}
