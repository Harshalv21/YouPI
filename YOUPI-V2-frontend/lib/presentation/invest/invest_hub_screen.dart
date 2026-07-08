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

class InvestHubScreen extends StatefulWidget {
  const InvestHubScreen({super.key});
  @override
  State<InvestHubScreen> createState() => _InvestHubScreenState();
}

class _InvestHubScreenState extends State<InvestHubScreen> {
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
          title: Text('Invest', style: AppTextStyles.headlineMedium),
          backgroundColor: AppColors.backgroundPrimary,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.paddingPage),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Gold price card
              YoupiGlassCard(
                child: Row(children: [
                  const Text('🪙', style: TextStyle(fontSize: 36)),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Digital Gold', style: AppTextStyles.labelMedium),
                    Text(CurrencyFormatter.format(vm.gold.pricePerGram),
                        style: AppTextStyles.amountMedium),
                    const Text('Per gram', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  ])),
                  Column(children: [
                    Icon(
                      vm.gold.isPriceUp ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded,
                      color: vm.gold.isPriceUp ? AppColors.success : AppColors.error,
                      size: 28,
                    ),
                    Text('${vm.gold.priceChange.toStringAsFixed(2)}%',
                        style: TextStyle(
                          color: vm.gold.isPriceUp ? AppColors.success : AppColors.error,
                          fontSize: 13,
                        )),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),
              YoupiButton(
                label: 'Buy / Sell Digital Gold',
                onPressed: () => ctx.push('/invest/gold'),
              ),
              const SizedBox(height: 24),
              Text('Investment Products', style: AppTextStyles.headlineSmall),
              const SizedBox(height: 12),
              YoupiCard(
                onTap: () => ctx.push('/invest/fd'),
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
                    Text('Fixed Deposits', style: AppTextStyles.labelLarge),
                    Text('Up to 7.5% p.a. | RBI Regulated', style: AppTextStyles.bodySmall),
                  ])),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                ]),
              ),
              const SizedBox(height: 10),
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
                    Text('My Portfolio', style: AppTextStyles.labelLarge),
                    Text('View all your investments', style: AppTextStyles.bodySmall),
                  ])),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                ]),
              ),
              const SizedBox(height: 24),
              if (!vm.isLoading) ...[
                Text('My Gold Balance', style: AppTextStyles.headlineSmall),
                const SizedBox(height: 12),
                YoupiCard(
                  showGlow: true,
                  child: Row(children: [
                    const Text('🏅', style: TextStyle(fontSize: 28)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${vm.gold.balanceGrams.toStringAsFixed(3)} grams', style: AppTextStyles.amountMedium),
                      Text('≈ ${CurrencyFormatter.format(vm.gold.balanceValue)}', style: AppTextStyles.bodySmall),
                    ])),
                  ]),
                ),
              ],
            ],
          ),
        ),
      );
    });
  }
}
