import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_card.dart';
import '../dashboard/home_viewmodel.dart';
import 'invest_viewmodel.dart';

class DigitalGoldScreen extends StatefulWidget {
  const DigitalGoldScreen({super.key});
  @override
  State<DigitalGoldScreen> createState() => _DigitalGoldScreenState();
}

class _DigitalGoldScreenState extends State<DigitalGoldScreen> {
  // Backend caches Augmont rates for 35s (RATES_TTL in InvestService.kt),
  // so polling every 30s here always gets a value that's at most one cache
  // cycle old, without hammering our own /gold/price endpoint.
  static const _pollInterval = Duration(seconds: 30);
  Timer? _pollTimer;

  static const _buyChips = [500.0, 1000.0, 2500.0, 5000.0];
  static const _sellChipFractions = [0.25, 0.5, 0.75, 1.0];
  static const _sellChipLabels = ['25%', '50%', '75%', 'All'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final investVm = context.read<InvestViewModel>();
      await investVm.loadGold();

      // The user can navigate away (hardware back, etc.) while loadGold()
      // is still in flight -- using context after that await without
      // checking mounted throws "widget has been unmounted" exactly as
      // seen in the crash log. Bail out cleanly instead.
      if (!mounted) return;

      // One-time (idempotent on the backend) mapping so buy/sell doesn't
      // fail with "Augmont user not mapped" for accounts that have never
      // transacted before -- nothing else in the app does this yet.
      final user = context.read<HomeViewModel>().user;
      if (user.name.isNotEmpty && user.mobile.isNotEmpty) {
        await investVm.ensureAugmontUser(
          name: user.name,
          email: user.email,
          mobile: user.mobile,
        );
      }
    });
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (mounted) context.read<InvestViewModel>().loadGold();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _showEditAmountDialog(BuildContext context, InvestViewModel vm) async {
    final controller = TextEditingController(text: vm.buyAmount.toStringAsFixed(0));
    final result = await showDialog<double>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.backgroundCard,
        title: Text(vm.isGoldBuy ? 'Enter buy amount' : 'Enter sell amount', style: AppTextStyles.labelLarge),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: AppTextStyles.amountMedium,
          decoration: const InputDecoration(prefixText: '₹', hintText: 'e.g. 2000'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, double.tryParse(controller.text)),
            child: const Text('Done'),
          ),
        ],
      ),
    );
    if (result != null && result > 0) vm.setBuyAmount(result);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InvestViewModel>(builder: (ctx, vm, _) {
      // Buy and Sell show different live rates -- Augmont quotes them
      // separately, they're never identical.
      final isBuy = vm.isGoldBuy;
      final displayRate = isBuy ? vm.gold.pricePerGram : vm.gold.sellRatePerGram;
      final modeColor = isBuy ? AppColors.primary : AppColors.error;

      // Sell can't exceed what the user actually holds -- clamp the slider
      // range to current holdings value instead of the fixed ₹50,000 buy
      // ceiling.
      final sellMax = vm.gold.balanceValue > 100 ? vm.gold.balanceValue : 100.0;
      final sliderMax = isBuy ? 50000.0 : sellMax;
      final sliderValue = vm.buyAmount.clamp(100.0, sliderMax);

      final goldLeftAfterSell = (vm.gold.balanceGrams - vm.gramsForBuyAmount).clamp(0, double.infinity);

      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(
          title: const Text('24K Digital Gold'),
          backgroundColor: AppColors.backgroundPrimary,
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

                // ── Rate card ─────────────────────────────────────────
                _RateCard(
                  label: isBuy ? 'BUY RATE' : 'SELL RATE',
                  rate: displayRate,
                  color: modeColor,
                ),

                const SizedBox(height: 16),
                // Balance card -- real holdings, updates after every buy/sell
                YoupiCard(
                  child: Row(children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: const Text('🪙', style: TextStyle(fontSize: 18)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('MY GOLD BALANCE', style: AppTextStyles.captionText.copyWith(color: AppColors.textSecondary)),
                        Text(
                          '${vm.gold.balanceGrams.toStringAsFixed(3)} g ≈ ${CurrencyFormatter.format(vm.gold.balanceValue)}',
                          style: AppTextStyles.labelLarge,
                        ),
                      ]),
                    ),
                  ]),
                ),

                const SizedBox(height: 20),
                // Buy/Sell capsule toggle
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundCard,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => vm.setIsGoldBuy(true),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isBuy ? AppColors.primary : Colors.transparent,
                            borderRadius: BorderRadius.circular(26),
                          ),
                          child: Text('BUY', textAlign: TextAlign.center,
                              style: TextStyle(
                                color: isBuy ? AppColors.backgroundPrimary : AppColors.textSecondary,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              )),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => vm.setIsGoldBuy(false),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: !isBuy ? AppColors.error : Colors.transparent,
                            borderRadius: BorderRadius.circular(26),
                          ),
                          child: Text('SELL', textAlign: TextAlign.center,
                              style: TextStyle(
                                color: !isBuy ? AppColors.backgroundPrimary : AppColors.textSecondary,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              )),
                        ),
                      ),
                    ),
                  ]),
                ),

                const SizedBox(height: 24),
                Text(isBuy ? 'BUY AMOUNT' : 'SELL AMOUNT',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.captionText.copyWith(color: AppColors.textSecondary, letterSpacing: 1)),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(CurrencyFormatter.format(vm.buyAmount), style: AppTextStyles.amountLarge),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => _showEditAmountDialog(ctx, vm),
                    child: Container(
                      width: 30, height: 30,
                      decoration: const BoxDecoration(color: AppColors.backgroundCard, shape: BoxShape.circle),
                      child: const Icon(Icons.edit_rounded, size: 15, color: AppColors.textSecondary),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.secondary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isBuy ? 'You get ${vm.gramsForBuyAmount.toStringAsFixed(4)} g' : 'You sell ${vm.gramsForBuyAmount.toStringAsFixed(4)} g',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondary, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: modeColor,
                    inactiveTrackColor: AppColors.divider,
                    thumbColor: Colors.white,
                    overlayColor: modeColor.withOpacity(0.2),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: sliderValue.toDouble(),
                    min: 100,
                    max: sliderMax,
                    onChanged: vm.setBuyAmount,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(4, (i) {
                    final label = isBuy ? CurrencyFormatter.format(_buyChips[i]) : _sellChipLabels[i];
                    return GestureDetector(
                      onTap: () => vm.setBuyAmount(
                        isBuy ? _buyChips[i] : (vm.gold.balanceValue * _sellChipFractions[i]).clamp(100, sellMax),
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundCard,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(label, style: AppTextStyles.bodySmall),
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 24),
                if (isBuy)
                  YoupiCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('SECURITY & FEATURES', style: AppTextStyles.captionText.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 14),
                      for (final f in ['MMTC-PAMP 24K gold, 99.9% pure', 'Instant demat credit', 'SG vaulted & insured'])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(children: [
                            Container(
                              width: 22, height: 22,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.check_rounded, color: AppColors.primary, size: 14),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(f, style: AppTextStyles.bodySmall)),
                          ]),
                        ),
                    ]),
                  )
                else
                  YoupiCard(
                    child: Column(children: [
                      _InfoRow('Gold left after sell', '${goldLeftAfterSell.toStringAsFixed(4)} g'),
                      const Divider(color: AppColors.divider, height: 22),
                      // NOTE: no linked-bank-account field exists anywhere in
                      // the app yet (checked HomeViewModel/WalletRepository)
                      // -- placeholder until a real "settlement account" API
                      // exists to read this from.
                      const _InfoRow('Credited to', 'HDFC ••4417'),
                      const Divider(color: AppColors.divider, height: 22),
                      const _InfoRow('Settlement', '1–2 working days'),
                    ]),
                  ),

                const SizedBox(height: 20),
                YoupiButton(
                  label: '${isBuy ? 'Buy' : 'Sell'} gold for ${CurrencyFormatter.format(vm.buyAmount)}',
                  isLoading: vm.isLoading,
                  onPressed: () async {
                    final ok = await vm.transactGold();
                    if (ok && ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                        content: Text(isBuy ? 'Gold purchased!' : 'Gold sold!'),
                        backgroundColor: AppColors.success,
                      ));
                      // Optimistic update already happened in transactGold();
                      // this replaces it with the server-confirmed balance.
                      await vm.loadGold();
                      if (ctx.mounted) ctx.pop();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _RateCard extends StatelessWidget {
  final String label;
  final double rate;
  final Color color;
  const _RateCard({required this.label, required this.rate, required this.color});

  @override
  Widget build(BuildContext context) {
    final formatted = CurrencyFormatter.format(rate);
    final dotIndex = formatted.lastIndexOf('.');
    final whole = dotIndex == -1 ? formatted : formatted.substring(0, dotIndex);
    final decimals = dotIndex == -1 ? '' : formatted.substring(dotIndex);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppColors.backgroundPrimary,
        border: Border.all(color: color.withOpacity(0.28)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.09), AppColors.backgroundPrimary],
        ),
        boxShadow: [BoxShadow(color: color.withOpacity(0.12), blurRadius: 24, spreadRadius: -14)],
      ),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text('$label · LIVE',
              style: AppTextStyles.captionText.copyWith(color: AppColors.textSecondary, letterSpacing: 1, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 8),
        RichText(
          text: TextSpan(children: [
            TextSpan(text: whole, style: AppTextStyles.amountLarge),
            TextSpan(text: decimals, style: AppTextStyles.amountLarge.copyWith(color: AppColors.textSecondary, fontSize: (AppTextStyles.amountLarge.fontSize ?? 32) * 0.55)),
          ]),
        ),
        const SizedBox(height: 4),
        Text('per gram', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
      Text(value, style: AppTextStyles.labelLarge),
    ]);
  }
}