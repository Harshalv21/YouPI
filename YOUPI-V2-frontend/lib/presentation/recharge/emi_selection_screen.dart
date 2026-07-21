import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_card.dart';
import 'recharge_viewmodel.dart';

class EmiSelectionScreen extends StatelessWidget {
  const EmiSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RechargeViewModel>(builder: (ctx, vm, _) {
      final plan = vm.selectedPlan;
      if (plan == null) return const Scaffold(body: Center(child: Text('No plan selected')));

      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(backgroundColor: AppColors.backgroundPrimary,
            title: Text('EMI Selection', style: AppTextStyles.headlineMedium)),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.paddingPage),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tier badge
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.secondary),
                  ),
                  child: Text('OBSIDIAN',
                      style: AppTextStyles.labelLarge.copyWith(color: AppColors.secondary, letterSpacing: 3)),
                ),
              ),
              const SizedBox(height: 20),
              Text('Investment Summary', style: AppTextStyles.headlineLarge, textAlign: TextAlign.center),
              Text('Review your periodic payment details.',
                  style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              // Portfolio card
              YoupiGlassCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Portfolio', style: AppTextStyles.labelMedium),
                  Text('₹8,42,000', style: AppTextStyles.amountMedium),
                  Row(children: [
                    const Icon(Icons.trending_up_rounded, color: AppColors.success, size: 14),
                    const SizedBox(width: 4),
                    Text('Portfolio Growth +12.4%',
                        style: AppTextStyles.captionText.copyWith(color: AppColors.success)),
                  ]),
                ]),
              ),
              const SizedBox(height: 20),
              Text('Recent Activity', style: AppTextStyles.headlineSmall),
              const SizedBox(height: 8),
              YoupiCard(
                child: Text('${plan.operator.toUpperCase()} ₹${plan.price.toStringAsFixed(0)} | ${plan.dataPerDay}/day | ${plan.validityDays} days',
                    style: AppTextStyles.bodyMedium),
              ),
              const SizedBox(height: 20),
              Text('Choose EMI Plan', style: AppTextStyles.headlineSmall),
              const SizedBox(height: 12),
              if (plan.emiOptions.isEmpty)
                YoupiCard(
                  child: Text('Full payment: ₹${plan.price.toStringAsFixed(0)}', style: AppTextStyles.labelLarge),
                )
              else
                ...plan.emiOptions.map((emi) {
                  final selected = vm.selectedEmi?.months == emi.months;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GestureDetector(
                      onTap: () => vm.selectEmi(emi),
                      child: YoupiCard(
                        showGlow: selected,
                        borderColor: selected ? AppColors.primary : null,
                        child: Row(children: [
                          Icon(
                            selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                            color: selected ? AppColors.primary : AppColors.textSecondary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Text(emi.label, style: AppTextStyles.labelLarge),
                                if (emi.isRecommended) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('RECOMMENDED',
                                        style: AppTextStyles.labelSmall.copyWith(
                                            color: AppColors.backgroundPrimary, fontSize: 9)),
                                  ),
                                ],
                              ]),
                              Text('Total ₹${emi.totalAmount.toStringAsFixed(0)} • ${emi.feeLabel}',
                                  style: AppTextStyles.bodySmall),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  );
                }).toList(),
              const SizedBox(height: 8),
              Text('First EMI deducted today via auto-debit',
                  style: AppTextStyles.captionText, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              YoupiButton(
                label: vm.paymentInProgress ? 'Confirming payment...' : 'Confirm & Proceed',
                isLoading: vm.isLoading || vm.paymentInProgress,
                onPressed: () async {
                  final ok = await vm.payAndConfirm();
                  if (!ctx.mounted) return;
                  if (ok) {
                    ctx.go('/plans/success');
                  } else if (vm.error != null) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(vm.error!)),
                    );
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