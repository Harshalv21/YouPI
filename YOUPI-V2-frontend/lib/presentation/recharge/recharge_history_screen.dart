// lib/presentation/recharge/recharge_history_screen.dart
//
// Recharge History feature — YouPI V2
// Uses the app's real theme constants (AppColors / AppTextStyles) instead
// of a local duplicate, to avoid import collisions with
// core/constants/app_colors.dart.

import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';

// ---------------------------------------------------------------------------
// MODEL
// ---------------------------------------------------------------------------
enum RechargeStatus { success, failed, pending }

class RechargeRecord {
  final String id;
  final String mobileNumber;
  final String operator;
  final String circle;
  final double amount;
  final String planDescription;
  final String validity;
  final String paymentMethod;
  final String paymentTxnId;
  final RechargeStatus status;
  final String? failureReason;
  final double? goldCoinsEarned;
  final DateTime createdAt;

  RechargeRecord({
    required this.id,
    required this.mobileNumber,
    required this.operator,
    required this.circle,
    required this.amount,
    required this.planDescription,
    required this.validity,
    required this.paymentMethod,
    required this.paymentTxnId,
    required this.status,
    this.failureReason,
    this.goldCoinsEarned,
    required this.createdAt,
  });
}

// ---------------------------------------------------------------------------
// STATUS BADGE
// ---------------------------------------------------------------------------
class StatusBadge extends StatelessWidget {
  final RechargeStatus status;
  const StatusBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    late Color color;
    late String label;
    switch (status) {
      case RechargeStatus.success:
        color = AppColors.primary;
        label = 'Success';
        break;
      case RechargeStatus.failed:
        color = AppColors.error;
        label = 'Failed';
        break;
      case RechargeStatus.pending:
        color = AppColors.secondary;
        label = 'Pending';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String formatShortDate(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${dt.day} ${months[dt.month - 1]}';
}

String formatFullDateTime(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  final minute = dt.minute.toString().padLeft(2, '0');
  return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $hour:$minute $ampm';
}

// ---------------------------------------------------------------------------
// FULL RECHARGE HISTORY SCREEN ("View All")
// ---------------------------------------------------------------------------
class RechargeHistoryScreen extends StatefulWidget {
  final List<RechargeRecord> allRecords;

  const RechargeHistoryScreen({super.key, required this.allRecords});

  @override
  State<RechargeHistoryScreen> createState() => _RechargeHistoryScreenState();
}

class _RechargeHistoryScreenState extends State<RechargeHistoryScreen> {
  RechargeStatus? _filter; // null = All

  List<RechargeRecord> get _filtered {
    if (_filter == null) return widget.allRecords;
    return widget.allRecords.where((r) => r.status == _filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundPrimary,
        elevation: 0,
        title: Text('Recharge History', style: AppTextStyles.headlineMedium),
      ),
      body: Column(
        children: [
          _buildFilterChips(),
          const SizedBox(height: 8),
          Expanded(
            child: _filtered.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final r = _filtered[index];
                      return _RechargeHistoryTile(
                        record: r,
                        onTap: () => _showDetail(context, r),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final options = <String, RechargeStatus?>{
      'All': null,
      'Success': RechargeStatus.success,
      'Failed': RechargeStatus.failed,
      'Pending': RechargeStatus.pending,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: options.entries.map((e) {
          final selected = _filter == e.value;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(e.key),
              selected: selected,
              onSelected: (_) => setState(() => _filter = e.value),
              selectedColor: AppColors.primary.withOpacity(0.18),
              backgroundColor: AppColors.backgroundCard,
              labelStyle: AppTextStyles.labelSmall.copyWith(
                color: selected ? AppColors.primary : AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
              side: BorderSide(
                color: selected
                    ? AppColors.primary
                    : AppColors.textSecondary.withOpacity(0.15),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 48, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(
            'No recharges found',
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context, RechargeRecord record) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => RechargeDetailSheet(record: record),
    );
  }
}

class _RechargeHistoryTile extends StatelessWidget {
  final RechargeRecord record;
  final VoidCallback onTap;

  const _RechargeHistoryTile({required this.record, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.backgroundCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.textSecondary.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.backgroundPrimary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.phone_android, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(record.mobileNumber, style: AppTextStyles.labelLarge),
                      const SizedBox(width: 6),
                      Text(
                        '• ${record.operator}',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatShortDate(record.createdAt),
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₹${record.amount.toStringAsFixed(0)}', style: AppTextStyles.headlineSmall),
                const SizedBox(height: 6),
                StatusBadge(status: record.status),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// DETAIL BOTTOM SHEET
// ---------------------------------------------------------------------------
class RechargeDetailSheet extends StatelessWidget {
  final RechargeRecord record;
  const RechargeDetailSheet({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${record.operator} • ${record.circle}', style: AppTextStyles.headlineSmall),
              StatusBadge(status: record.status),
            ],
          ),
          const SizedBox(height: 4),
          Text(record.mobileNumber, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          _detailRow('Plan', record.planDescription),
          _detailRow('Validity', record.validity),
          _detailRow('Amount Paid', '₹${record.amount.toStringAsFixed(2)}'),
          _detailRow('Payment Method', record.paymentMethod),
          _detailRow('Transaction ID', record.paymentTxnId),
          _detailRow('Date & Time', formatFullDateTime(record.createdAt)),
          if (record.status == RechargeStatus.failed && record.failureReason != null)
            _detailRow('Reason', record.failureReason!, valueColor: AppColors.error),
          if (record.status == RechargeStatus.success && record.goldCoinsEarned != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Text('🪙', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Text(
                      '+${record.goldCoinsEarned!.toStringAsFixed(0)} gold coins earned',
                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          if (record.status == RechargeStatus.failed)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  // TODO: wire to retry recharge flow with same params
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Retry Recharge',
                    style: AppTextStyles.labelLarge.copyWith(color: AppColors.backgroundPrimary)),
              ),
            ),
          if (record.status == RechargeStatus.pending)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  // TODO: wire to refresh status API call
                },
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppColors.secondary),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Refresh Status',
                    style: AppTextStyles.labelLarge.copyWith(color: AppColors.secondary)),
              ),
            ),
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () {
                // TODO: wire to support/help flow
              },
              child: Text(
                'Get Help',
                style: AppTextStyles.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: AppTextStyles.bodySmall.copyWith(
                color: valueColor ?? AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}