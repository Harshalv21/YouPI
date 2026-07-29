import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_card.dart';
import 'gold_coin_reward_screen.dart';
import 'recharge_viewmodel.dart';

// EMI options removed for this version -- full-amount-only, per launch
// scope. The backend/paymentMode enum still technically support
// EMI_3/6/12 for a future version; this screen just no longer offers
// them -- it always confirms with PaymentMode.FULL.
class EmiSelectionScreen extends StatelessWidget {
  const EmiSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RechargeViewModel>(builder: (ctx, vm, _) {
      final plan = vm.selectedPlan;
      if (plan == null) return const Scaffold(body: Center(child: Text('No plan selected')));

      // Force full payment -- no EMI path offered this version.
      vm.selectFullPayment();

      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(backgroundColor: AppColors.backgroundPrimary,
            title: Text('Confirm Recharge', style: AppTextStyles.headlineMedium)),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.paddingPage),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              Text(
                'Full amount charged immediately via Razorpay Checkout',
                style: AppTextStyles.captionText,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              YoupiButton(
                label: vm.paymentInProgress ? 'Confirming payment...' : 'Confirm & Pay ₹${plan.price.toStringAsFixed(0)}',
                isLoading: vm.isLoading || vm.paymentInProgress,
                onPressed: () async {
                  final ok = await vm.payAndConfirm();
                  if (!ctx.mounted) return;
                  if (ok) {
                    // Matches backend's GOLD_ELIGIBLE_PLAN_AMOUNT (>= ₹249,
                    // see RechargeService.kt) -- only qualifying recharges
                    // get the coin-toss celebration.
                    if (plan.price >= 249) {
                      // Overlay on THIS screen (dimmed background, per
                      // design) rather than navigating to a separate page
                      // -- await it, then go home once it's done/skipped.
                      await showGoldCoinReward(ctx, plan.price);
                      if (!ctx.mounted) return;
                      ctx.go('/dashboard/home');
                    } else {
                      ctx.go('/plans/success');
                    }
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