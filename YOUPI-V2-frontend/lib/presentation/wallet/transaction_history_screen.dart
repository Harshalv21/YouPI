import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/youpi_card.dart';
import '../../data/models/transaction_model.dart';
import '../invest/invest_viewmodel.dart';
import 'transaction_detail_sheet.dart';

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
    final grouped = _groupByDate(vm.transactions);

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
        // ← Date-grouped ("Today" / "Yesterday" / date) sections -- this is
        // the full history list, so grouping by day belongs here (the
        // compact "Recent Transactions" preview on the Wallet home screen
        // stays flat, no headers, to keep it short).
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppDimensions.paddingPage),
          children: grouped.entries.expand((entry) => [
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Text(entry.key,
                  style: AppTextStyles.labelSmall.copyWith(
                      color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
            ),
            ...entry.value.map((tx) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TransactionTile(tx),
            )),
          ]).toList(),
        ),
      ),
    );
  }
}

// ── Groups a (already-sorted-newest-first) transaction list into labeled
// buckets: "Today", "Yesterday", else "12 Aug 2026" -- preserves order,
// doesn't re-sort.
Map<String, List<TransactionModel>> _groupByDate(List<TransactionModel> txs) {
  final map = <String, List<TransactionModel>>{};
  for (final tx in txs) {
    final label = _dateGroupLabel(tx.dateTime);
    map.putIfAbsent(label, () => []).add(tx);
  }
  return map;
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _dateGroupLabel(DateTime dt) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final txDate = DateTime(dt.year, dt.month, dt.day);
  if (txDate == today) return 'Today';
  if (txDate == yesterday) return 'Yesterday';
  return '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
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
    // ← Split-recharge ka title row mein simplify ho jaata hai (mobile
    // number tak, "wallet portion ₹X of ₹Y" wala part hat jaata hai --
    // wo detail sheet mein poora breakdown ke saath dikhta hai).
    final split = tx.splitRechargeDetails;
    final displayTitle = split != null ? 'Split Recharge ${split.mobileNumber}' : tx.title;

    return YoupiCard(
      onTap: () => showTransactionDetailSheet(context, tx),
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
          Text(displayTitle, style: AppTextStyles.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text('${tx.category} • ${_formatTime(tx.dateTime)}', style: AppTextStyles.bodySmall),
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