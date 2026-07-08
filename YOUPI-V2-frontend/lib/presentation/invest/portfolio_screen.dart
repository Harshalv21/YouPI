import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/youpi_card.dart';
import 'invest_viewmodel.dart';

class PortfolioScreen extends StatelessWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<InvestViewModel>(builder: (ctx, vm, _) {
      final totalValue = vm.gold.balanceValue + 100000;
      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(title: const Text('My Portfolio'), backgroundColor: AppColors.backgroundPrimary),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.paddingPage),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YoupiGlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Total Portfolio Value', style: AppTextStyles.labelMedium),
                  Text(CurrencyFormatter.format(totalValue), style: AppTextStyles.amountLarge),
                  const SizedBox(height: 8),
                  Row(children: [
                    const Icon(Icons.trending_up_rounded, color: AppColors.success, size: 16),
                    const SizedBox(width: 4),
                    Text('+₹8,420 this month', style: AppTextStyles.bodySmall.copyWith(color: AppColors.success)),
                  ]),
                ]),
              ),
              const SizedBox(height: 24),
              Text('Breakdown', style: AppTextStyles.headlineSmall),
              const SizedBox(height: 12),
              _AssetRow('Digital Gold', '🪙', vm.gold.balanceValue, vm.gold.balanceValue / totalValue, AppColors.secondary),
              const SizedBox(height: 10),
              _AssetRow('Fixed Deposits', '🏦', 100000, 100000 / totalValue, AppColors.primary),
              const SizedBox(height: 10),
              _AssetRow('BNPL Limit', '💳', 5000, 5000 / totalValue, AppColors.primary.withOpacity(0.7)),
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
          LinearProgressIndicator(value: percent, backgroundColor: AppColors.divider,
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
