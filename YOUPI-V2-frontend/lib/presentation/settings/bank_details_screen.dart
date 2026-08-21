import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../data/repositories/user_repository.dart';

/// Settings > Bank Account.
///
/// REDESIGN: previously a single "verified detail" card. Now matches the
/// GPay/PhonePe "Payment methods" list pattern requested by Harshal --
/// a linked-account list row (bank icon, name, account type, Primary/
/// Verified badge) plus a dashed "Add bank account" action tile, with
/// the full masked details available as an expandable section below the
/// row instead of always-on.
class BankDetailsScreen extends StatefulWidget {
  const BankDetailsScreen({super.key});

  @override
  State<BankDetailsScreen> createState() => _BankDetailsScreenState();
}

class _BankDetailsScreenState extends State<BankDetailsScreen> {
  final _userRepo = UserRepository();
  KycDetailsResult? _details;
  bool _loading = true;
  String? _error;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _userRepo.getKycDetails();
      setState(() => _details = result);
    } catch (e) {
      setState(() => _error = 'Could not load your bank details. Pull to retry.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = _details;
    final hasBank = d != null && d.bankVerified;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundPrimary,
        title: Text('Bank Account', style: AppTextStyles.headlineSmall),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: _loading
            ? const Center(
          child: Padding(
            padding: EdgeInsets.only(top: 100),
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        )
            : ListView(
          padding: const EdgeInsets.all(AppDimensions.paddingPage),
          children: [
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(_error!,
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
              ),
            Text('UPI PAYMENTS',
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.textSecondary, letterSpacing: 0.6)),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: AppColors.backgroundCard,
                borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                children: [
                  if (hasBank)
                    _BankListRow(
                      bankName: d.bankName ?? 'Bank Account',
                      subtitle: 'Savings account',
                      isPrimary: true,
                      expanded: _expanded,
                      onTap: () => setState(() => _expanded = !_expanded),
                    ),
                  if (hasBank && _expanded) ...[
                    const Divider(height: 1, color: AppColors.divider),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DetailRow(
                            label: 'Account Number',
                            value: d.bankAccountLast4 != null
                                ? 'XXXXXXXX${d.bankAccountLast4}'
                                : '—',
                          ),
                          const SizedBox(height: 12),
                          _DetailRow(label: 'IFSC Code', value: d.bankIfsc ?? '—'),
                          const SizedBox(height: 12),
                          _DetailRow(
                              label: 'Account Holder',
                              value: d.bankAccountHolderName ?? '—'),
                        ],
                      ),
                    ),
                  ],
                  if (hasBank) const Divider(height: 1, color: AppColors.divider),
                  _DashedAddTile(
                    icon: Icons.account_balance_outlined,
                    label: hasBank ? 'Add another bank account' : 'Add bank account',
                    onTap: () => context.push('/kyc/bank-account'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Your bank account is used for refunds, gold redemption payouts, '
                  'and loan disbursement. Verified securely via Eko.',
              style: AppTextStyles.captionText,
            ),
          ],
        ),
      ),
    );
  }
}

/// A single linked-account row, styled like GPay/PhonePe's payment methods
/// list: square bank-icon avatar on the left, name + account type in the
/// middle, a "Primary" pill and a chevron on the right.
class _BankListRow extends StatelessWidget {
  final String bankName;
  final String subtitle;
  final bool isPrimary;
  final bool expanded;
  final VoidCallback onTap;

  const _BankListRow({
    required this.bankName,
    required this.subtitle,
    required this.isPrimary,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.account_balance_rounded, color: AppColors.primary, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bankName, style: AppTextStyles.labelLarge),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(subtitle,
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                      if (isPrimary) ...[
                        const SizedBox(width: 8),
                        Text('Primary',
                            style: AppTextStyles.captionText.copyWith(color: AppColors.textSecondary)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 12),
                  const SizedBox(width: 4),
                  Text('Verified',
                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.success, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }
}

/// The GPay/PhonePe-style dashed "add" row — icon in a dashed square,
/// label to the right. Flutter has no built-in dashed border, so this is
/// drawn with a small CustomPainter rather than pulling in a package.
class _DashedAddTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DashedAddTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            CustomPaint(
              painter: _DashedBoxPainter(color: AppColors.primary, radius: 10),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
            ),
            const SizedBox(width: 14),
            Text(label, style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
          ],
        ),
      ),
    );
  }
}

class _DashedBoxPainter extends CustomPainter {
  final Color color;
  final double radius;
  const _DashedBoxPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(radius),
    );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final path = Path()..addRRect(rrect);
    const dashWidth = 4.0;
    const dashGap = 3.0;
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(metric.extractPath(distance, next.clamp(0, metric.length)), paint);
        distance = next + dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBoxPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
        Text(value, style: AppTextStyles.labelLarge),
      ],
    );
  }
}
