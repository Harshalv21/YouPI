import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/youpi_card.dart';
import '../../data/datasources/mock_data.dart';
import '../../data/models/transaction_model.dart';

class TransactionHistoryScreen extends StatelessWidget {
  const TransactionHistoryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(title: const Text('Transaction History'), backgroundColor: AppColors.backgroundPrimary),
      body: ListView.separated(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        itemCount: MockData.mockTransactions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) => _TransactionTile(MockData.mockTransactions[i]),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  final TransactionModel tx;
  const _TransactionTile(this.tx);
  @override
  Widget build(BuildContext context) {
    return YoupiCard(
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: tx.isCredit ? AppColors.success.withOpacity(0.1) : AppColors.backgroundSurface,
            shape: BoxShape.circle,
          ),
          child: Icon(
            tx.isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
            color: tx.isCredit ? AppColors.success : AppColors.error,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tx.title, style: AppTextStyles.labelLarge),
          Text(tx.category, style: AppTextStyles.bodySmall),
        ])),
        Text(
          '${tx.isCredit ? '+' : '-'}${CurrencyFormatter.format(tx.amount)}',
          style: AppTextStyles.labelLarge.copyWith(
            color: tx.isCredit ? AppColors.success : AppColors.error),
        ),
      ]),
    );
  }
}
