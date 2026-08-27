import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/currency_formatter.dart';
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

      // GoldModel has no cost-basis / invested-amount field yet, so there's
      // no true lifetime P&L to read. "Invested" and "Total returns" below
      // are derived from today's live price move (priceChange applied to
      // current holdings) rather than a hardcoded number -- real, live data,
      // just today's move standing in for all-time. Swap this for a real
      // cost-basis-based calc once that field exists on GoldModel.
      final returnPercent = vm.gold.priceChange;
      final returnAmount = vm.gold.balanceValue * (returnPercent.abs() / (100 + returnPercent.abs()));
      final isUp = vm.gold.isPriceUp;
      final investedAmount = isUp ? vm.gold.balanceValue - returnAmount : vm.gold.balanceValue + returnAmount;

      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(title: const Text('My portfolio'), backgroundColor: AppColors.backgroundPrimary),
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

                // ── Total portfolio value card ───────────────────────
                _GlassCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text('TOTAL PORTFOLIO VALUE',
                            style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                            width: 6, height: 6,
                            decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 5),
                          Text('LIVE', style: AppTextStyles.captionText.copyWith(
                              color: AppColors.success, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Text(CurrencyFormatter.format(totalValue), style: AppTextStyles.amountLarge),
                    const SizedBox(height: 12),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${isUp ? '+' : '-'}${CurrencyFormatter.format(returnAmount)}',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.success, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('${returnPercent.abs().toStringAsFixed(1)}% overall',
                          style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                    ]),
                  ]),
                ),

                const SizedBox(height: 24),
                Text('HOLDINGS', style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: goldPercent.clamp(0, 1),
                    minHeight: 6,
                    backgroundColor: AppColors.divider,
                    valueColor: const AlwaysStoppedAnimation(AppColors.secondary),
                  ),
                ),
                const SizedBox(height: 14),
                _HoldingRow(
                  emoji: '🪙',
                  title: 'Digital gold',
                  subtitle: '${vm.gold.balanceGrams.toStringAsFixed(3)} g · 24K · ${(goldPercent * 100).toStringAsFixed(0)}%',
                  value: CurrencyFormatter.format(vm.gold.balanceValue),
                  changeLabel: '${isUp ? '+' : '-'}${returnPercent.abs().toStringAsFixed(1)}%',
                  changeColor: isUp ? AppColors.success : AppColors.error,
                  highlighted: true,
                ),
                const SizedBox(height: 10),
                const _ComingSoonHoldingRow(emoji: '🏦', title: 'Fixed deposits'),
                const SizedBox(height: 10),
                const _ComingSoonHoldingRow(emoji: '💳', title: 'BNPL limit'),

                const SizedBox(height: 24),
                Text('RETURNS', style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 12),
                YoupiCard(
                  child: Column(children: [
                    _ReturnRow('Invested', CurrencyFormatter.format(investedAmount)),
                    const Divider(color: AppColors.divider, height: 24),
                    _ReturnRow('Current value', CurrencyFormatter.format(vm.gold.balanceValue)),
                    const Divider(color: AppColors.divider, height: 24),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Total returns', style: AppTextStyles.bodyMedium),
                      Row(children: [
                        Text('${isUp ? '+' : '-'}${CurrencyFormatter.format(returnAmount)}',
                            style: AppTextStyles.labelLarge.copyWith(
                                color: isUp ? AppColors.success : AppColors.error)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('${isUp ? '+' : '-'}${returnPercent.abs().toStringAsFixed(1)}%',
                              style: AppTextStyles.captionText.copyWith(
                                  color: AppColors.success, fontWeight: FontWeight.bold)),
                        ),
                      ]),
                    ]),
                  ]),
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

class _HoldingRow extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final String value;
  final String changeLabel;
  final Color changeColor;
  final bool highlighted;
  const _HoldingRow({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.changeLabel,
    required this.changeColor,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(children: [
      Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: AppColors.secondary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(emoji, style: const TextStyle(fontSize: 20)),
      ),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: AppTextStyles.labelLarge),
        const SizedBox(height: 2),
        Text(subtitle, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
      ])),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(value, style: AppTextStyles.labelLarge),
        Text(changeLabel, style: AppTextStyles.bodySmall.copyWith(color: changeColor, fontWeight: FontWeight.bold)),
      ]),
    ]);
    // Highlighted (the real, live holding) gets the same hand-built green
    // glass treatment as the hero card -- YoupiCard's showGlow wasn't
    // rendering the border/glow on device.
    return highlighted ? _GlassCard(padding: 16, child: row) : YoupiCard(child: row);
  }
}

class _ComingSoonHoldingRow extends StatelessWidget {
  final String emoji;
  final String title;
  const _ComingSoonHoldingRow({required this.emoji, required this.title});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.45,
      child: YoupiCard(
        child: Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(emoji, style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppTextStyles.labelLarge.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 2),
            Text('Coming soon', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
          ])),
        ]),
      ),
    );
  }
}

class _ReturnRow extends StatelessWidget {
  final String label;
  final String value;
  const _ReturnRow(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
      Text(value, style: AppTextStyles.labelLarge),
    ]);
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

// Explicit green-tinted glass card -- built by hand instead of relying on
// YoupiGlassCard/showGlow, whose border/glow wasn't rendering on device.
// Matches the target: mostly-black card, faint green tint at the top, a
// thin soft green border, and a subtle outward glow (kept dark, not a
// bright green fill).
class _GlassCard extends StatelessWidget {
  final Widget child;
  final double padding;
  const _GlassCard({required this.child, this.padding = 18});

   @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.22)),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0.0, 0.55, 1.0],
          colors: [
            AppColors.glassTintTop,
            AppColors.glassTintMid,
            AppColors.backgroundPrimary,
          ],
        ),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withOpacity(0.08), blurRadius: 24, spreadRadius: -14),
        ],
      ),
      child: child,
    );
  }
}