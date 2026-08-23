import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/guest_guard.dart';
import '../../core/widgets/youpi_card.dart';
import '../../data/models/transaction_model.dart';
import '../invest/invest_viewmodel.dart';
import 'transaction_detail_sheet.dart';

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
    final recentTx = vm.transactions.take(6).toList();

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
            // ── Balance card -- single "Add money" action lives inside the
            // card now. Wallet only ever funds recharges (no send/transfer/
            // investment out of it), so a second quick-action button next
            // to it would be a button with nothing to do -- dropped it.
            YoupiGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Available balance', style: AppTextStyles.captionText),
                  const SizedBox(height: 6),
                  Text(CurrencyFormatter.format(vm.balance), style: AppTextStyles.amountLarge),
                  const SizedBox(height: 16),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      if (!await GuestGuard.requireAuth(context, actionLabel: 'add money')) return;
                      if (context.mounted) context.push('/wallet/add');
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.primary.withOpacity(0.35)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_rounded, color: AppColors.primary, size: 18),
                          const SizedBox(width: 8),
                          Text('Add money',
                              style: AppTextStyles.labelSmall.copyWith(
                                  color: AppColors.primary, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('Recent Transactions', style: AppTextStyles.headlineSmall),
              TextButton(
                onPressed: () => context.push('/wallet/history'),
                child: Text('View All', style: AppTextStyles.tealLink.copyWith(decoration: TextDecoration.none)),
              ),
            ]),
            const SizedBox(height: 4),
            if (recentTx.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('No transactions yet', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                ),
              )
            else
              // ← Flat list, no date headers -- this is just a compact
              // preview (max 6 items), not the full history. Grouping by
              // day here was making the home screen itself scroll like a
              // history page; grouping now lives on the Transaction
              // History screen instead, where it belongs.
              ...recentTx.map((tx) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _TransactionTile(tx),
              )),
          ]),
        ),
      ),
    );
  }
}

String _formatTime(DateTime dt) {
  final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  return '$hour12:$minute $ampm';
}

class _TransactionTile extends StatelessWidget {
  final TransactionModel tx;
  const _TransactionTile(this.tx);

  @override
  Widget build(BuildContext context) {
    // ← Split-recharge ka title simplify hota hai (mobile number tak --
    // "wallet portion ₹X of ₹Y" wala part hat jaata hai, wo detail sheet
    // mein poora breakdown ke saath dikhta hai).
    final split = tx.splitRechargeDetails;
    final displayTitle = split != null ? 'Split Recharge ${split.mobileNumber}' : tx.title;

    // ← Wallet se sirf recharge hoti hai (koi transfer/investment out of
    // wallet nahi) -- to category icon simple hai: debit == recharge
    // (phone icon), credit == money added (down-arrow). Amount ka
    // red/green already semantic hai, icon bas usi color ko match karta
    // hai taaki visually ek hi story dikhe.
    final icon = tx.isCredit ? Icons.arrow_downward_rounded : Icons.smartphone_rounded;
    final color = tx.isCredit ? AppColors.success : AppColors.error;

    return YoupiCard(
      onTap: () => showTransactionDetailSheet(context, tx),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 17),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(displayTitle, style: AppTextStyles.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 1),
          Text(_formatTime(tx.dateTime), style: AppTextStyles.captionText.copyWith(color: AppColors.textSecondary)),
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