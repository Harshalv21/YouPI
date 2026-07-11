import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/youpi_card.dart';
import '../../data/models/transaction_model.dart';
import '../invest/invest_viewmodel.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});
  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  @override
  void initState() {
    super.initState();
    // Wallet tab already loads this on entry, but load fresh in case this
    // screen is opened before the wallet tab ever ran.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm = context.read<WalletViewModel>();
      if (vm.transactions.isEmpty && !vm.isLoading) {
        vm.loadWallet();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WalletViewModel>();

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(title: const Text('Transaction History'), backgroundColor: AppColors.backgroundPrimary),
      body: vm.isLoading && vm.transactions.isEmpty
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : vm.transactions.isEmpty
          ? Center(
        child: Text('No transactions yet',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
      )
          : RefreshIndicator(
        onRefresh: () => vm.loadWallet(),
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppDimensions.paddingPage),
          itemCount: vm.transactions.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (ctx, i) => _TransactionTile(vm.transactions[i]),
        ),
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