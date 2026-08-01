// lib/presentation/recharge/recharge_history_screen.dart
//
// Recharge History feature — YouPI V2
// Uses the app's real theme constants (AppColors / AppTextStyles) instead
// of a local duplicate, to avoid import collisions with
// core/constants/app_colors.dart.

import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import '../../core/constants/app_colors.dart';
import '../../data/repositories/recharge_repository.dart';
import '../../core/constants/app_text_styles.dart';

// ---------------------------------------------------------------------------
// CONTACT LOOKUP -- resolves a phone number to the matching device contact's
// name, so history rows can show a name-initial avatar instead of a generic
// phone icon. Contacts are fetched once (name+phone only) and cached.
//
// NOTE: photo support was attempted here but removed -- this project's
// installed flutter_contacts version doesn't expose a per-id getContact()
// or a photoOrThumbnail getter (both were unresolved-reference errors).
// Only the properties:{...} form of getAll() is confirmed to work (it's
// already used successfully elsewhere in this project). If real contact
// photos are wanted later, paste pubspec.yaml's flutter_contacts version
// pin and this can be re-added against the correct API surface.
// ---------------------------------------------------------------------------
class ContactLookup {
  static List<Contact>? _cache;

  static Future<List<Contact>> _all() async {
    if (_cache != null) return _cache!;
    await FlutterContacts.permissions.request(PermissionType.read);
    final granted = await FlutterContacts.permissions.has(PermissionType.read);
    if (!granted) {
      _cache = [];
      return _cache!;
    }
    try {
      _cache = await FlutterContacts.getAll(properties: {ContactProperty.name, ContactProperty.phone});
    } catch (_) {
      _cache = [];
    }
    return _cache!;
  }

  static String _last10(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
  }

  /// Matches by trailing 10 digits (handles +91 prefixes either side).
  static Future<Contact?> matchNumber(String mobileNumber) async {
    final contacts = await _all();
    final target = _last10(mobileNumber);
    if (target.isEmpty) return null;
    for (final c in contacts) {
      for (final p in c.phones) {
        if (_last10(p.number) == target) return c;
      }
    }
    return null;
  }
}

// Avatar that resolves a phone number to the matching contact's name
// initial. (Photo support removed -- see ContactLookup note above.)
class ContactAvatar extends StatelessWidget {
  final String mobileNumber;
  final double radius;

  const ContactAvatar({super.key, required this.mobileNumber, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Contact?>(
      future: ContactLookup.matchNumber(mobileNumber),
      builder: (context, snapshot) {
        final contact = snapshot.data;
        final name = contact?.displayName ?? '';
        final initial = name.isNotEmpty ? name[0].toUpperCase() : (mobileNumber.isNotEmpty ? mobileNumber[0] : '#');
        return CircleAvatar(
          radius: radius,
          backgroundColor: AppColors.primary.withValues(alpha: 0.15),
          child: Text(initial, style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary)),
        );
      },
    );
  }
}


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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
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
  final RechargeRepository _repo = RechargeRepository();
  late List<RechargeRecord> _records;

  @override
  void initState() {
    super.initState();
    _records = List.of(widget.allRecords);
  }

  Future<void> _confirmAndClear() async {
    if (_records.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.backgroundCard,
        title: Text('Clear history?', style: AppTextStyles.headlineSmall),
        content: Text(
          'This hides your recharge history from this screen. Your transaction '
              'records stay safe on our servers and aren\'t deleted.',
          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('Clear', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.hideFromHistory(_records.map((r) => r.id));
    if (!mounted) return;
    setState(() => _records = []);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundPrimary,
        elevation: 0,
        title: Text('Recharge History', style: AppTextStyles.headlineMedium),
        actions: [
          if (_records.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Clear history',
              onPressed: _confirmAndClear,
            ),
        ],
      ),
      body: _records.isEmpty
          ? _buildEmptyState()
          : ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _records.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final r = _records[index];
          return _RechargeHistoryTile(
            record: r,
            onTap: () => _showDetail(context, r),
          );
        },
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
          border: Border.all(color: AppColors.textSecondary.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            ContactAvatar(mobileNumber: record.mobileNumber, radius: 20),
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
                color: AppColors.textSecondary.withValues(alpha: 0.2),
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
                  color: AppColors.primary.withValues(alpha: 0.1),
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