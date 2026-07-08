import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_card.dart';
import '../../data/datasources/mock_data.dart';

class BnplHubScreen extends StatelessWidget {
  const BnplHubScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final bnpl = MockData.mockBnpl;
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(title: const Text('Buy Now Pay Later'), backgroundColor: AppColors.backgroundPrimary),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            YoupiGlassCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('💳', style: TextStyle(fontSize: 24)),
                  const SizedBox(width: 8),
                  Text('BNPL Card', style: AppTextStyles.labelMedium),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppColors.success),
                    ),
                    child: Text('ACTIVE', style: AppTextStyles.labelSmall.copyWith(color: AppColors.success)),
                  ),
                ]),
                const SizedBox(height: 12),
                Text('Available Limit', style: AppTextStyles.captionText),
                Text(CurrencyFormatter.format(bnpl.available), style: AppTextStyles.amountMedium),
                const SizedBox(height: 8),
                Text('${(bnpl.usedPercent * 100).toStringAsFixed(0)}% used out of ₹${bnpl.limit.toStringAsFixed(0)}',
                    style: AppTextStyles.bodySmall),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: bnpl.usedPercent,
                  backgroundColor: AppColors.divider,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                ),
              ]),
            ),
            const SizedBox(height: 24),
            Text('Quick Actions', style: AppTextStyles.headlineSmall),
            const SizedBox(height: 12),
            Row(children: [
              _BnplAction('Apply for Limit Increase', Icons.upgrade_rounded, () => context.push('/bnpl/apply/step1')),
              const SizedBox(width: 12),
              _BnplAction('Smart Deposit', Icons.savings_rounded, () => context.push('/bnpl/smart-deposit')),
            ]),
            const SizedBox(height: 24),
            Text('Where to Use BNPL', style: AppTextStyles.headlineSmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ['Mobile Recharge', 'Gold Purchase', 'Online Shopping', 'Bill Payments', 'Travel']
                  .map((s) => Chip(
                    label: Text(s, style: AppTextStyles.chipText),
                    backgroundColor: AppColors.backgroundCard,
                    side: const BorderSide(color: AppColors.divider),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  )).toList(),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.secondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.secondary.withOpacity(0.4)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('SmartDeposit Feature', style: AppTextStyles.labelLarge.copyWith(color: AppColors.secondary)),
                const SizedBox(height: 4),
                const Text('Earn 6% interest on unused BNPL limit while not using it.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 10),
                YoupiButton(
                  label: 'Enable SmartDeposit',
                  height: 40,
                  onPressed: () => context.push('/bnpl/smart-deposit'),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _BnplAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _BnplAction(this.label, this.icon, this.onTap);
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: YoupiCard(onTap: onTap, child: Column(children: [
        Icon(icon, color: AppColors.primary, size: 24),
        const SizedBox(height: 6),
        Text(label, style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
      ])),
    );
  }
}
