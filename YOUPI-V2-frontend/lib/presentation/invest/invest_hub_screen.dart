import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/youpi_card.dart';
import 'invest_viewmodel.dart';

class InvestHubScreen extends StatefulWidget {
  const InvestHubScreen({super.key});
  @override
  State<InvestHubScreen> createState() => _InvestHubScreenState();
}

class _InvestHubScreenState extends State<InvestHubScreen> {
  // Backend caches Augmont rates for 35s (RATES_TTL in InvestService.kt),
  // so polling every 30s here always gets a value that's at most one cache
  // cycle old, without hammering our own /gold/price endpoint.
  static const _pollInterval = Duration(seconds: 30);
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) =>
        context.read<InvestViewModel>().loadGold());
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (mounted) context.read<InvestViewModel>().loadGold();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InvestViewModel>(builder: (ctx, vm, _) {
      // NOTE: GoldModel has no cost-basis / invested-amount field yet, so
      // there's no way to compute a true lifetime gain. balanceValue stands
      // in for "invested" in the header pill, and "Total gain" is derived
      // from today's live price move (priceChange applied to the current
      // holdings) rather than a hardcoded number -- it's real, live data,
      // just today's move instead of true all-time P&L. Swap this for a
      // real cost-basis-based calc once that field exists on GoldModel.
      final gainPercent = vm.gold.priceChange;
      final gainAmount = vm.gold.balanceValue * (gainPercent.abs() / (100 + gainPercent.abs()));
      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(
          title: Text('Invest', style: AppTextStyles.headlineMedium),
          backgroundColor: AppColors.backgroundPrimary,
          actions: [
            Container(
              margin: const EdgeInsets.only(right: AppDimensions.paddingPage),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.backgroundCard,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(
                '${CurrencyFormatter.format(vm.gold.balanceValue)} invested',
                style: AppTextStyles.bodySmall,
              ),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () => ctx.read<InvestViewModel>().loadGold(),
          color: AppColors.primary,
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

                // ── Gold price card ──────────────────────────────────
                _GlassCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        alignment: Alignment.center,
                        child: const Text('🪙', style: TextStyle(fontSize: 22)),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Digital gold', style: AppTextStyles.labelLarge),
                          Text('24K · per gram', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                        ]),
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
                    const SizedBox(height: 18),
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Expanded(child: Text(CurrencyFormatter.format(vm.gold.pricePerGram), style: AppTextStyles.amountLarge)),
                      Row(children: [
                        Icon(
                          vm.gold.isPriceUp ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                          color: vm.gold.isPriceUp ? AppColors.success : AppColors.error,
                          size: 20,
                        ),
                        Text('${vm.gold.priceChange.abs().toStringAsFixed(2)}% today',
                            style: AppTextStyles.bodySmall.copyWith(
                              color: vm.gold.isPriceUp ? AppColors.success : AppColors.error,
                            )),
                      ]),
                    ]),
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              vm.setIsGoldBuy(true);
                              ctx.push('/invest/gold');
                            },
                            child: Text('Buy gold',
                                style: AppTextStyles.labelLarge.copyWith(
                                    color: AppColors.backgroundPrimary, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: AppColors.textSecondary.withOpacity(0.3)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () {
                              vm.setIsGoldBuy(false);
                              ctx.push('/invest/gold');
                            },
                            child: Text('Sell', style: AppTextStyles.labelLarge.copyWith(fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    ]),
                  ]),
                ),

                const SizedBox(height: 24),
                if (!vm.isLoading) ...[
                  Text('My Gold Balance', style: AppTextStyles.headlineSmall),
                  const SizedBox(height: 12),
                  _GlassCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${vm.gold.balanceGrams.toStringAsFixed(2)} g', style: AppTextStyles.amountMedium),
                            const SizedBox(height: 2),
                            Text('≈ ${CurrencyFormatter.format(vm.gold.balanceValue)} current value',
                                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                          ]),
                        ),
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.secondary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: const Text('🪙', style: TextStyle(fontSize: 18)),
                        ),
                      ]),
                      const SizedBox(height: 14),
                      const Divider(color: AppColors.divider, height: 1),
                      const SizedBox(height: 14),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('Total gain', style: AppTextStyles.bodyMedium),
                        Text(
                          '${vm.gold.isPriceUp ? '+' : '-'}${CurrencyFormatter.format(gainAmount)} · ${gainPercent.abs().toStringAsFixed(1)}%',
                          style: AppTextStyles.labelLarge.copyWith(
                              color: vm.gold.isPriceUp ? AppColors.success : AppColors.error),
                        ),
                      ]),
                    ]),
                  ),
                ],

                const SizedBox(height: 24),
                Text('More Products', style: AppTextStyles.headlineSmall),
                const SizedBox(height: 12),
                YoupiCard(
                  onTap: () => ctx.push('/invest/portfolio'),
                  child: Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.pie_chart_rounded, color: AppColors.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('My portfolio', style: AppTextStyles.labelLarge),
                      Text('Holdings and returns', style: AppTextStyles.bodySmall),
                    ])),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                  ]),
                ),
                const SizedBox(height: 10),
                // Goal Saving now opens the real (if backend-less) Goals
                // screen instead of a "coming soon" snackbar.
                YoupiCard(
                  onTap: () => ctx.push('/invest/goals'),
                  child: Row(children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.flag_rounded, color: AppColors.secondary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Goal saving', style: AppTextStyles.labelLarge),
                      Text('Save in gold for what you want', style: AppTextStyles.bodySmall),
                    ])),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                  ]),
                ),
                const SizedBox(height: 10),
                // Per latest instruction: Fixed Deposits is dimmed and
                // non-navigable here now (even though fd_calculator_screen
                // itself still exists/works if reached another way) --
                // matches the same dimmed "Coming soon" treatment already
                // used for FD/BNPL on portfolio_screen.dart.
                Opacity(
                  opacity: 0.45,
                  child: YoupiCard(
                    onTap: () => ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Fixed deposits is coming soon')),
                    ),
                    child: Row(children: [
                      Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.account_balance_rounded, color: AppColors.secondary),
                      ),
                      const SizedBox(width: 14),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Fixed deposits', style: AppTextStyles.labelLarge),
                        Text('Coming soon', style: AppTextStyles.bodySmall),
                      ])),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

// Explicit green-tinted glass card -- built by hand instead of relying on
// YoupiGlassCard, whose border/glow wasn't rendering on device for this
// screen. Matches the target: mostly-black card, faint green tint at the
// top, a thin soft green border, and a subtle outward glow (kept dark, not
// a bright green fill).
class _GlassCard extends StatelessWidget {
  final Widget child;
  const _GlassCard({required this.child});

    @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
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