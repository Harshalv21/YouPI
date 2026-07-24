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

      // Full payment is "selected" whenever no EMI option is currently
      // chosen. This mirrors how the backend decides paymentMode
      // (FULL vs EMI_x) purely from whether an EMI is set.
      final isFullPaymentSelected = vm.selectedEmi == null;

      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(backgroundColor: AppColors.backgroundPrimary,
            title: Text('Payment Options', style: AppTextStyles.headlineMedium)),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.paddingPage),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Recharge summary -- what's actually being paid for.
              YoupiCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(plan.name, style: AppTextStyles.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    '${plan.operator.toUpperCase()} • ${plan.dataPerDay}/day • ${plan.validityDays} days',
                    style: AppTextStyles.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  Text('₹${plan.price.toStringAsFixed(0)}',
                      style: AppTextStyles.amountMedium.copyWith(color: AppColors.primary)),
                ]),
              ),
              const SizedBox(height: 24),
              Text('Choose Payment Option', style: AppTextStyles.headlineSmall),
              const SizedBox(height: 12),

              // Pay in full -- always offered, regardless of whether EMI
              // options exist for this plan.
              GestureDetector(
                onTap: () => vm.selectFullPayment(),
                child: YoupiCard(
                  showGlow: isFullPaymentSelected,
                  borderColor: isFullPaymentSelected ? AppColors.primary : null,
                  child: Row(children: [
                    Icon(
                      isFullPaymentSelected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: isFullPaymentSelected ? AppColors.primary : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Pay Full Amount', style: AppTextStyles.labelLarge),
                        Text('₹${plan.price.toStringAsFixed(0)} • Charged now, one time',
                            style: AppTextStyles.bodySmall),
                      ]),
                    ),
                  ]),
                ),
              ),

              if (plan.emiOptions.isNotEmpty) ...[
                const SizedBox(height: 10),
                ...plan.emiOptions.map((emi) {
                  final selected = !isFullPaymentSelected && vm.selectedEmi?.months == emi.months;
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
                                Flexible(child: Text(emi.label, style: AppTextStyles.labelLarge)),
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
              ],

              const SizedBox(height: 8),
              Text(
                isFullPaymentSelected
                    ? 'Full amount charged immediately via Razorpay Checkout'
                    : 'First EMI deducted today via auto-debit',
                style: AppTextStyles.captionText,
                textAlign: TextAlign.center,
              ),
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