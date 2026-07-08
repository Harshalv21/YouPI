import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_card.dart';
import '../../data/datasources/mock_data.dart';

class MyLoansScreen extends StatelessWidget {
  const MyLoansScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final loan = MockData.mockLoan;
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(title: const Text('My Loans'), backgroundColor: AppColors.backgroundPrimary),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          YoupiGlassCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Active Personal Loan', style: AppTextStyles.labelMedium),
              Text(CurrencyFormatter.format(loan.amount), style: AppTextStyles.amountLarge),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: loan.progressPercent,
                backgroundColor: AppColors.divider,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
              const SizedBox(height: 4),
              Text('${loan.emisPaid} of ${loan.tenureMonths} EMIs paid • ${loan.emisRemaining} remaining',
                  style: AppTextStyles.captionText),
            ]),
          ),
          const SizedBox(height: 20),
          YoupiCard(child: Column(children: [
            _Row('Monthly EMI', CurrencyFormatter.format(loan.monthlyEmi)),
            const Divider(color: AppColors.divider, height: 20),
            const _Row('Next EMI', '01 Apr 2026'),
            const Divider(color: AppColors.divider, height: 20),
            _Row('Interest Rate', '${loan.interestRate}% p.a.'),
          ])),
          const SizedBox(height: 20),
          YoupiButton(label: 'Pay EMI Now', onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('EMI payment initiated!'), backgroundColor: AppColors.success));
          }),
        ]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);
  @override Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: AppTextStyles.bodyMedium),
      Text(value, style: AppTextStyles.labelLarge),
    ],
  );
}
