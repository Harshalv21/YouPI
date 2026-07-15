import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/tap_to_edit_slider.dart';
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
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InvestViewModel>(builder: (ctx, vm, _) {
      // Buy and Sell show different live rates -- Augmont quotes them
      // separately, they're never identical.
      final displayRate = vm.isGoldBuy ? vm.gold.pricePerGram : vm.gold.sellRatePerGram;

      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(
          title: const Text('24K Digital Gold'),
          backgroundColor: AppColors.backgroundPrimary,
        ),
        body: SingleChildScrollView(
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
              // Price header
              YoupiGlassCard(
                child: Column(children: [
                  Text(vm.isGoldBuy ? 'Buy Rate' : 'Sell Rate', style: AppTextStyles.labelMedium),
                  Text(CurrencyFormatter.format(displayRate), style: AppTextStyles.amountLarge),
                  Text('/gram • LIVE RATE', style: AppTextStyles.captionText),
                ]),
              ),
              const SizedBox(height: 20),
              // Balance card -- real holdings, updates after every buy/sell
              YoupiCard(
                child: Row(children: [
                  const Text('🏅', style: TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('My Gold Balance', style: AppTextStyles.labelMedium),
                    Text('${vm.gold.balanceGrams.toStringAsFixed(3)} grams', style: AppTextStyles.headlineSmall),
                    Text(CurrencyFormatter.format(vm.gold.balanceValue), style: AppTextStyles.bodySmall),
                  ]),
                ]),
              ),
              const SizedBox(height: 20),
              // Buy/Sell toggle -- Buy stays the brand teal, Sell is a
              // proper vibrant red (AppColors.error), not a muddy dark red.
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => vm.setIsGoldBuy(true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: vm.isGoldBuy ? AppColors.primary : AppColors.backgroundCard,
                        borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
                      ),
                      child: Text('BUY', textAlign: TextAlign.center,
                          style: TextStyle(
                            color: vm.isGoldBuy ? AppColors.backgroundPrimary : AppColors.textSecondary,
                            fontWeight: FontWeight.bold,
                          )),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => vm.setIsGoldBuy(false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: !vm.isGoldBuy ? AppColors.error : AppColors.backgroundCard,
                        borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(12), bottomRight: Radius.circular(12)),
                      ),
                      child: Text('SELL', textAlign: TextAlign.center,
                          style: TextStyle(
                            color: !vm.isGoldBuy ? AppColors.backgroundPrimary : AppColors.textSecondary,
                            fontWeight: FontWeight.bold,
                          )),
                    ),
                  ),
                ),
              ]),
              const SizedBox(height: 20),
              Text(vm.isGoldBuy ? 'Buy Amount' : 'Sell Amount', style: AppTextStyles.labelMedium),
              const SizedBox(height: 4),
              TapToEditSlider(
                value: vm.buyAmount,
                min: 100,
                max: 50000,
                divisions: 499,
                activeColor: vm.isGoldBuy ? AppColors.primary : AppColors.error,
                onChanged: vm.setBuyAmount,
                displayFormatter: (v) => CurrencyFormatter.format(v),
                dialogTitle: vm.isGoldBuy ? 'Enter buy amount' : 'Enter sell amount',
                dialogHint: 'e.g. 2000',
              ),
              Text('≈ ${vm.gramsForBuyAmount.toStringAsFixed(4)} grams',
                  style: AppTextStyles.bodySmall),
              const SizedBox(height: 20),
              YoupiCard(
                child: Column(children: [
                  Text('Security & Features', style: AppTextStyles.labelLarge),
                  const SizedBox(height: 12),
                  for (final f in ['MMTC-PAMP 24K Gold (99.9% pure)', 'Instant demat credit', 'SG Vaulted & insured'])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 16),
                        const SizedBox(width: 8),
                        Text(f, style: AppTextStyles.bodySmall),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 20),
              YoupiButton(
                label: vm.isGoldBuy ? 'Buy Gold' : 'Sell Gold',
                isLoading: vm.isLoading,
                onPressed: () async {
                  final ok = await vm.transactGold();
                  if (ok && ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                      content: Text(vm.isGoldBuy ? 'Gold purchased!' : 'Gold sold!'),
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
      );
    });
  }
}