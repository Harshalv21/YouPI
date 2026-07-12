import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/guest_guard.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_card.dart';
import '../../data/models/transaction_model.dart';
import '../invest/invest_viewmodel.dart';

// ─────────── Shared widgets ───────────
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoRow(this.label, this.value, {this.valueColor});
  @override Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: AppTextStyles.bodyMedium),
      Text(value, style: AppTextStyles.labelLarge.copyWith(color: valueColor)),
    ],
  );
}

// ─────────── Wallet ───────────
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});
  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<WalletViewModel>().loadWallet();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WalletViewModel>();

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(title: const Text('My Wallet'), backgroundColor: AppColors.backgroundPrimary),
      body: vm.isLoading && vm.transactions.isEmpty
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
        onRefresh: () => vm.loadWallet(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppDimensions.paddingPage),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            YoupiGlassCard(
              child: Column(children: [
                const Icon(Icons.account_balance_wallet_rounded, color: AppColors.primary, size: 36),
                const SizedBox(height: 8),
                Text(CurrencyFormatter.format(vm.balance), style: AppTextStyles.amountLarge),
                Text('Available Balance', style: AppTextStyles.captionText),
              ]),
            ),
            const SizedBox(height: 20),
            Row(children: [
              _WalletAction('Add Money', Icons.add_circle_rounded, () async {
                if (!await GuestGuard.requireAuth(context, actionLabel: 'add money')) return;
                if (context.mounted) context.push('/wallet/add');
              }),
              const SizedBox(width: 10),
              _WalletAction('Send Money', Icons.send_rounded, () async {
                if (!await GuestGuard.requireAuth(context, actionLabel: 'send money')) return;
                if (context.mounted) context.push('/wallet/send');
              }),
              const SizedBox(width: 10),
              _WalletAction('Withdraw', Icons.download_rounded, () async {
                if (!await GuestGuard.requireAuth(context, actionLabel: 'withdraw money')) return;
                if (context.mounted) context.push('/wallet/withdraw');
              }),
            ]),
            const SizedBox(height: 24),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Recent Transactions', style: AppTextStyles.headlineSmall),
              TextButton(
                onPressed: () => context.push('/wallet/history'),
                child: Text('View All', style: AppTextStyles.tealLink.copyWith(decoration: TextDecoration.none)),
              ),
            ]),
            const SizedBox(height: 12),
            if (vm.transactions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No transactions yet', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                ),
              )
            else
              ...vm.transactions.take(6).map((tx) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TransactionTile(tx),
              )).toList(),
          ]),
        ),
      ),
    );
  }
}

class _WalletAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _WalletAction(this.label, this.icon, this.onTap);
  @override Widget build(BuildContext context) => Expanded(
    child: YoupiCard(onTap: onTap, padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(children: [
        Icon(icon, color: AppColors.primary, size: 22),
        const SizedBox(height: 4),
        Text(label, style: AppTextStyles.labelSmall),
      ]),
    ),
  );
}

class _TransactionTile extends StatelessWidget {
  final TransactionModel tx;
  const _TransactionTile(this.tx);
  @override Widget build(BuildContext context) => YoupiCard(
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