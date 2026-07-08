import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_card.dart';
import '../../core/widgets/youpi_input.dart';
import '../../data/datasources/mock_data.dart';
import '../../data/models/loan_model.dart';
import '../../core/utils/currency_formatter.dart';

// ─────────── Shared loan widget ───────────
class _LoanInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _LoanInfoRow(this.label, this.value, {this.valueColor});
  @override Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: AppTextStyles.bodyMedium),
      Text(value, style: AppTextStyles.labelLarge.copyWith(color: valueColor)),
    ],
  );
}

// ─────────── Step 1 ───────────
class LoanApplyStep1Screen extends StatelessWidget {
  const LoanApplyStep1Screen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(title: const Text('Personal Loan'), backgroundColor: AppColors.backgroundPrimary),
      body: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LinearProgressIndicator(value: 1 / 3, backgroundColor: AppColors.divider, valueColor: const AlwaysStoppedAnimation(AppColors.primary)),
          const SizedBox(height: 8),
          Text('Step 1 of 3 • Loan Details', style: AppTextStyles.labelMedium),
          const SizedBox(height: 24),
          const YoupiInput(label: 'Loan Amount', hint: '₹1,00,000', keyboardType: TextInputType.number),
          const SizedBox(height: 16),
          Text('Loan Tenure', style: AppTextStyles.inputLabel),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: ['3 months', '6 months', '12 months', '24 months'].map((t) =>
            FilterChip(
              label: Text(t, style: AppTextStyles.chipText),
              selected: t == '12 months',
              onSelected: (_) {},
              backgroundColor: AppColors.backgroundCard,
              selectedColor: AppColors.primary.withOpacity(0.2),
              side: BorderSide(color: t == '12 months' ? AppColors.primary : AppColors.divider),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            )).toList()),
          const SizedBox(height: 16),
          YoupiCard(showGlow: true, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Monthly EMI', style: AppTextStyles.labelMedium),
            Text('₹9,250', style: AppTextStyles.amountMedium),
            Text('14.5% p.a. | Total: ₹1,11,000', style: AppTextStyles.captionText),
          ])),
          const Spacer(),
          YoupiButton(label: 'Next', onPressed: () => context.push('/loan/apply/step2')),
        ]),
      ),
    );
  }
}

