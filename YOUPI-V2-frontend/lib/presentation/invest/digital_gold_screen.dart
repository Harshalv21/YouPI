import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_card.dart';
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
    WidgetsBinding.instance.addPostFrameCallback((_) =>
        context.read<InvestViewModel>().loadGold());
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<InvestViewModel>(builder: (ctx, vm, _) {
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
              // Price header
              YoupiGlassCard(
                child: Column(children: [
                  Text('Gold Price', style: AppTextStyles.labelMedium),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(CurrencyFormatter.format(vm.gold.pricePerGram), style: AppTextStyles.amountLarge),
                    const SizedBox(width: 6),
                    Icon(
                      vm.gold.isPriceUp ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                      color: vm.gold.isPriceUp ? AppColors.success : AppColors.error,
                    ),
                    Text('${vm.gold.priceChange.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: vm.gold.isPriceUp ? AppColors.success : AppColors.error,
                          fontSize: 12,
                        )),
                  ]),
                  Text('/gram • LIVE RATE', style: AppTextStyles.captionText),
                ]),
              ),
              const SizedBox(height: 20),
              // Balance card
              YoupiCard(
                child: Row(children: [
                  const Text('🏅', style: TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('My Gold', style: AppTextStyles.labelMedium),
                    Text('${vm.gold.balanceGrams.toStringAsFixed(3)} grams', style: AppTextStyles.headlineSmall),
                    Text(CurrencyFormatter.format(vm.gold.balanceValue), style: AppTextStyles.bodySmall),
                  ]),
                ]),
              ),
              const SizedBox(height: 20),
              // Buy/Sell toggle
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
                        color: !vm.isGoldBuy ? AppColors.primary : AppColors.backgroundCard,
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
              // Amount slider
              Text(vm.isGoldBuy ? 'Buy Amount' : 'Sell Amount', style: AppTextStyles.labelMedium),
              const SizedBox(height: 8),
              Text(CurrencyFormatter.format(vm.buyAmount), style: AppTextStyles.amountMedium),
              Slider(
                value: vm.buyAmount,
                min: 100,
                max: 50000,
                divisions: 499,
                activeColor: AppColors.primary,
                inactiveColor: AppColors.divider,
                onChanged: vm.setBuyAmount,
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
                    ctx.pop();
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
