import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_card.dart';
import '../../core/utils/currency_formatter.dart';

/// NBFC Credit dashboard -- shows the user's sanctioned credit limit,
/// the Free/Paid (20/80) breakdown, and recent usage on that limit.
/// Reached from Home via the "Credit" quick action and by tapping the
/// credit-limit card on Home.
///
/// TODO: this screen is fully hardcoded to match the design mock for now.
/// Wire it to real data (creditLimit, usedAmount, freeUsed, paidUsed,
/// nextDueDate, recent transactions) via a CreditViewModel/CreditRepository
/// once the Dikshi Finlease account-summary API is available -- same
/// backend that will eventually feed the Home credit-limit card.
class NbfcCreditScreen extends StatelessWidget {
  const NbfcCreditScreen({super.key});

  // ── Placeholder data -- matches the design mock ──
  static const double creditLimit = 10000;
  static const double usedAmount = 3200;
  static const double availableAmount = creditLimit - usedAmount;
  static const String nbfcName = 'DreamFin NBFC';
  static const String nextDueLabel = '5 Sep';

  static const double freeLimit = 2000;
  static const double freeUsed = 1200;
  static const double paidLimit = 8000;
  static const double paidUsed = 2000;

  static const _amberColor = Color(0xFFF2C94C);

  @override
  Widget build(BuildContext context) {
    final utilisedPct = ((usedAmount / creditLimit) * 100).round();
    final freeLeft = freeLimit - freeUsed;
    final paidLeft = paidLimit - paidUsed;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundPrimary,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => context.pop(),
        ),
        title: const Text('NBFC credit'),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Available to use ──
            YoupiGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Available to use', style: AppTextStyles.labelMedium),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(CurrencyFormatter.formatNoDecimal(availableAmount),
                          style: AppTextStyles.amountLarge),
                      const SizedBox(width: 8),
                      Text('of ${CurrencyFormatter.formatNoDecimal(creditLimit)}',
                          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${CurrencyFormatter.formatNoDecimal(usedAmount)} used · sanctioned by $nbfcName',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: usedAmount / creditLimit,
                      minHeight: 8,
                      backgroundColor: AppColors.divider,
                      valueColor: const AlwaysStoppedAnimation(_amberColor),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('$utilisedPct% utilised',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                      Text('Next due $nextDueLabel',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Limit breakdown', style: AppTextStyles.headlineSmall),
            const SizedBox(height: 12),

            // ── Free limit ──
            _LimitBreakdownCard(
              dotColor: AppColors.primary,
              title: 'Free limit',
              pctLabel: '20%',
              subtitle: 'Interest free · pay back anytime',
              amountLeft: freeLeft,
              amountLimit: freeLimit,
              amountUsed: freeUsed,
              progressColor: AppColors.primary,
            ),
            const SizedBox(height: 16),

            // ── Paid limit ──
            _LimitBreakdownCard(
              dotColor: AppColors.secondary,
              title: 'Paid limit',
              pctLabel: '80%',
              subtitle: 'Interest applicable · easy EMIs',
              amountLeft: paidLeft,
              amountLimit: paidLimit,
              amountUsed: paidUsed,
              progressColor: AppColors.secondary,
            ),
            const SizedBox(height: 16),

            // ── Summary note ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.backgroundCard,
                borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
              ),
              child: Text(
                'Free ${CurrencyFormatter.formatNoDecimal(freeLimit)} + paid ${CurrencyFormatter.formatNoDecimal(paidLimit)} = '
                'total exposure ${CurrencyFormatter.formatNoDecimal(creditLimit)}, as sanctioned by the NBFC.',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),

            // ── Recent usage ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Recent usage', style: AppTextStyles.headlineSmall),
                TextButton(
                  onPressed: () {},
                  child: Text('View all',
                      style: AppTextStyles.tealLink.copyWith(color: AppColors.textSecondary)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            YoupiCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                children: [
                  _UsageRow(
                    icon: Icons.smartphone_rounded,
                    iconColor: AppColors.primary,
                    title: 'Jio recharge',
                    subtitle: '12 Aug · free limit',
                    amountLabel: '-₹299',
                    amountColor: AppColors.textPrimary,
                  ),
                  const Divider(color: AppColors.divider, height: 1),
                  _UsageRow(
                    icon: Icons.smartphone_rounded,
                    iconColor: AppColors.secondary,
                    title: 'Airtel recharge',
                    subtitle: '8 Aug · paid limit',
                    amountLabel: '-₹749',
                    amountColor: AppColors.textPrimary,
                  ),
                  const Divider(color: AppColors.divider, height: 1),
                  _UsageRow(
                    icon: Icons.check_circle_rounded,
                    iconColor: AppColors.primary,
                    title: 'Repayment received',
                    subtitle: '5 Aug',
                    amountLabel: '+₹500',
                    amountColor: AppColors.primary,
                    isLast: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // ── CTAs ──
            Row(
              children: [
                Expanded(
                  child: YoupiButton(
                    label: 'Repay now',
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Repayment flow coming soon'),
                        backgroundColor: AppColors.backgroundCard,
                      ));
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: YoupiButton(
                    label: 'Request increase',
                    type: YoupiButtonType.ghost,
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Limit increase request coming soon'),
                        backgroundColor: AppColors.backgroundCard,
                      ));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _LimitBreakdownCard extends StatelessWidget {
  final Color dotColor;
  final String title;
  final String pctLabel;
  final String subtitle;
  final double amountLeft;
  final double amountLimit;
  final double amountUsed;
  final Color progressColor;

  const _LimitBreakdownCard({
    required this.dotColor,
    required this.title,
    required this.pctLabel,
    required this.subtitle,
    required this.amountLeft,
    required this.amountLimit,
    required this.amountUsed,
    required this.progressColor,
  });

  @override
  Widget build(BuildContext context) {
    final usedRatio = amountLimit > 0 ? (amountUsed / amountLimit).clamp(0.0, 1.0) : 0.0;

    return YoupiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(top: 5),
                      decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(title, style: AppTextStyles.labelLarge.copyWith(color: dotColor)),
                          const SizedBox(width: 6),
                          Text(pctLabel,
                              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(CurrencyFormatter.formatNoDecimal(amountLeft), style: AppTextStyles.amountMedium),
                  Text('left of ${CurrencyFormatter.formatNoDecimal(amountLimit)}',
                      style: AppTextStyles.captionText.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 14),
            child: Text(subtitle, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: usedRatio,
              minHeight: 6,
              backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation(progressColor),
            ),
          ),
          const SizedBox(height: 8),
          Text('${CurrencyFormatter.formatNoDecimal(amountUsed)} used',
              style: AppTextStyles.captionText.copyWith(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _UsageRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String amountLabel;
  final Color amountColor;
  final bool isLast;

  const _UsageRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.amountLabel,
    required this.amountColor,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: isLast ? 14 : 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.labelLarge),
                Text(subtitle, style: AppTextStyles.captionText.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Text(amountLabel, style: AppTextStyles.labelLarge.copyWith(color: amountColor)),
        ],
      ),
    );
  }
}