import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/transaction_model.dart';

// ← NAYA: Split-recharge (aur baaki) transactions ka full detail --
// half-page bottom sheet jo row pe tap karne se khulta hai. List row
// simple rehta hai (sirf title + amount), poora breakdown/time yaha
// dikhta hai.
Future<void> showTransactionDetailSheet(BuildContext context, TransactionModel tx) {
  final split = tx.splitRechargeDetails;
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.backgroundCard,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.textSecondary.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),

              // Icon + amount, centered like a receipt header
              Center(
                child: Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: tx.isCredit
                        ? AppColors.success.withOpacity(0.1)
                        : AppColors.backgroundSurface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    tx.isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                    color: tx.isCredit ? AppColors.success : AppColors.error,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Text(
                  '${tx.isCredit ? '+' : '-'}${CurrencyFormatter.format(tx.amount)}',
                  style: AppTextStyles.amountMedium.copyWith(
                    color: tx.isCredit ? AppColors.success : AppColors.error,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  split != null ? 'Split Recharge ${split.mobileNumber}' : tx.title,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.labelLarge,
                ),
              ),
              const SizedBox(height: 24),

              // ── Breakdown (only for split recharges) ──
              if (split != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withOpacity(0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Payment breakdown',
                          style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 10),
                      _DetailRow('From Wallet', CurrencyFormatter.format(split.walletPortion)),
                      const SizedBox(height: 6),
                      _DetailRow('Via UPI/Card (Gateway)', CurrencyFormatter.format(split.gatewayPortion)),
                      const Divider(height: 20),
                      _DetailRow('Total Recharge', CurrencyFormatter.format(split.totalAmount), bold: true),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ── Meta info ──
              _DetailRow('Status', _capitalize(tx.status)),
              const SizedBox(height: 10),
              _DetailRow('Date & Time', _formatDateTime(tx.dateTime)),
              const SizedBox(height: 10),
              _DetailRow('Category', tx.category),
              if (tx.id.isNotEmpty) ...[
                const SizedBox(height: 10),
                _DetailRow('Transaction ID', tx.id, small: true),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  final bool small;
  const _DetailRow(this.label, this.value, {this.bold = false, this.small = false});

  @override
  Widget build(BuildContext context) {
    final valueStyle = small
        ? AppTextStyles.captionText.copyWith(color: AppColors.textSecondary)
        : (bold
        ? AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700)
        : AppTextStyles.bodyMedium);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
        Flexible(
          child: Text(value, style: valueStyle, textAlign: TextAlign.right),
        ),
      ],
    );
  }
}

String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _formatDateTime(DateTime dt) {
  final day = dt.day.toString().padLeft(2, '0');
  final month = _months[dt.month - 1];
  final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  return '$day $month ${dt.year} • $hour12:$minute $ampm';
}