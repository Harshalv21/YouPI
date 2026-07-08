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

class FdCalculatorScreen extends StatelessWidget {
  const FdCalculatorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<InvestViewModel>(builder: (ctx, vm, _) {
      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(title: const Text('Fixed Deposit'), backgroundColor: AppColors.backgroundPrimary),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.paddingPage),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              YoupiCard(
                showGlow: true,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Expected Maturity', style: AppTextStyles.labelMedium),
                  Text(CurrencyFormatter.format(vm.fdMaturity), style: AppTextStyles.amountLarge),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Principal', style: AppTextStyles.bodySmall),
                      Text(CurrencyFormatter.format(vm.fdAmount), style: AppTextStyles.labelLarge),
                    ])),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Interest Earned', style: AppTextStyles.bodySmall),
                      Text(CurrencyFormatter.format(vm.interestEarned),
                          style: AppTextStyles.labelLarge.copyWith(color: AppColors.success)),
                    ])),
                  ]),
                ]),
              ),
              const SizedBox(height: 20),
              Text('Deposit Amount', style: AppTextStyles.labelMedium),
              Slider(
                value: vm.fdAmount,
                min: 1000,
                max: 500000,
                divisions: 499,
                activeColor: AppColors.primary,
                inactiveColor: AppColors.divider,
                onChanged: vm.setFdAmount,
              ),
              Text(CurrencyFormatter.format(vm.fdAmount), style: AppTextStyles.headlineSmall),
              const SizedBox(height: 16),
              Text('Tenure: ${vm.fdMonths} Months', style: AppTextStyles.labelMedium),
              Slider(
                value: vm.fdMonths.toDouble(),
                min: 3,
                max: 60,
                divisions: 57,
                activeColor: AppColors.primary,
                inactiveColor: AppColors.divider,
                onChanged: (v) => vm.setFdMonths(v.round()),
              ),
              const SizedBox(height: 16),
              Text('Interest Rate', style: AppTextStyles.labelMedium),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [5.0, 5.5, 6.0, 6.5, 7.0, 7.5, 8.0].map((r) =>
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => vm.setFdRate(r),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: vm.fdRate == r ? AppColors.primary : AppColors.backgroundCard,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: vm.fdRate == r ? AppColors.primary : AppColors.divider),
                          ),
                          child: Text('$r%',
                              style: AppTextStyles.chipText.copyWith(
                                color: vm.fdRate == r ? AppColors.backgroundPrimary : AppColors.textPrimary)),
                        ),
                      ),
                    )).toList(),
                ),
              ),
              const SizedBox(height: 20),
              // Partner banks
              Text('Partner Banks', style: AppTextStyles.headlineSmall),
              const SizedBox(height: 12),
              Row(children: ['Axis Bank — 7.5%', 'HDFC — 7.2%', 'ICICI — 7.0%'].map((b) =>
                Expanded(child: YoupiCard(padding: const EdgeInsets.all(10),
                    child: Text(b, style: AppTextStyles.bodySmall, textAlign: TextAlign.center)))).toList()),
              const SizedBox(height: 20),
              YoupiButton(
                label: 'Open FD Now',
                isLoading: vm.isLoading,
                onPressed: () async {
                  final ok = await vm.openFd();
                  if (ok && ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text('FD opened successfully!'), backgroundColor: AppColors.success));
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
