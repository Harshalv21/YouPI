import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/coming_soon_overlay.dart';
import '../../core/widgets/youpi_card.dart';
import 'invest_viewmodel.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});

  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  @override
  void initState() {
    super.initState();
    // Real-time: refresh gold price+holdings every time this page opens,
    // rather than trusting whatever was last loaded elsewhere.
    WidgetsBinding.instance.addPostFrameCallback((_) =>
        context.read<InvestViewModel>().loadGold());
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InvestViewModel>(builder: (ctx, vm, _) {
      // FD and BNPL aren't backed by real data yet (both are Coming Soon --
      // see fd_calculator_screen.dart / director's BNPL Credit Limit note),
      // so they contribute ₹0 here rather than a fabricated figure. Digital
      // Gold is the only genuinely real, live number on this page.
      const fdValue = 0.0;
      const bnplValue = 0.0;
      final totalValue = vm.gold.balanceValue + fdValue + bnplValue;
      final goldPercent = totalValue > 0 ? vm.gold.balanceValue / totalValue : 0.0;

      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(title: const Text('My Portfolio'), backgroundColor: AppColors.backgroundPrimary),
        body: RefreshIndicator(
          onRefresh: () => vm.loadGold(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppDimensions.paddingPage),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (vm.error != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.error.withOpacity(0.3)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.error, size: 16),
                      const SizedBox(width: 8),
                      Expanded(child: Text(vm.error!, style: AppTextStyles.bodySmall.copyWith(color: AppColors.error))),
                    ]),
                  ),
                YoupiGlassCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Total Portfolio Value', style: AppTextStyles.labelMedium),
                    Text(CurrencyFormatter.format(totalValue), style: AppTextStyles.amountLarge),
                    const SizedBox(height: 8),
                    Text('Live from your Digital Gold holdings',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                  ]),
                ),
                const SizedBox(height: 24),
                Text('Breakdown', style: AppTextStyles.headlineSmall),
                const SizedBox(height: 12),
                _AssetRow('Digital Gold', '🪙', vm.gold.balanceValue, goldPercent, AppColors.secondary),
                const SizedBox(height: 10),
                ComingSoonOverlay(
                  iconSize: 16,
                  showLabel: false,
                  child: _AssetRow('Fixed Deposits', '🏦', fdValue, 0, AppColors.primary),
                ),
                const SizedBox(height: 10),
                ComingSoonOverlay(
                  iconSize: 16,
                  showLabel: false,
                  child: _AssetRow('BNPL Limit', '💳', bnplValue, 0, AppColors.primary.withOpacity(0.7)),
                ),
                const SizedBox(height: 24),
                Text('Performance', style: AppTextStyles.headlineSmall),
                const SizedBox(height: 12),
                YoupiCard(
                  child: Column(children: [
                    _PerfRow('1M Return', '+4.2%', AppColors.success),
                    const Divider(color: AppColors.divider, height: 20),
                    _PerfRow('3M Return', '+12.4%', AppColors.success),
                    const Divider(color: AppColors.divider, height: 20),
                    _PerfRow('All Time', '+28.6%', AppColors.success),
                  ]),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _AssetRow extends StatelessWidget {
  final String label;
  final String emoji;
  final double value;
  final double percent;
  final Color color;
  const _AssetRow(this.label, this.emoji, this.value, this.percent, this.color);
  @override
  Widget build(BuildContext context) {
    return YoupiCard(
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: AppTextStyles.labelLarge),
          const SizedBox(height: 4),
          LinearProgressIndicator(value: percent.clamp(0, 1), backgroundColor: AppColors.divider,
              valueColor: AlwaysStoppedAnimation(color)),
        ])),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(CurrencyFormatter.format(value), style: AppTextStyles.labelLarge.copyWith(color: color)),
          Text('${(percent * 100).toStringAsFixed(1)}%', style: AppTextStyles.captionText),
        ]),
      ]),
    );
  }
}

class _PerfRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _PerfRow(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: AppTextStyles.bodyMedium),
      Text(value, style: AppTextStyles.labelLarge.copyWith(color: color)),
    ]);
  }
}