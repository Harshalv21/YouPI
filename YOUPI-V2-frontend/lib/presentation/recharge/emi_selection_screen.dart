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

  // ── TEMPORARY PREVIEW TOGGLE ──
  // true  = skip Razorpay/backend entirely, jump straight to the coin-toss
  //         animation. Zero payment, zero A1Topup call, zero risk -- purely
  //         to eyeball the animation running for real in the app.
  // false = normal real flow (Razorpay Checkout -> webhook -> A1Topup ->
  //         animation only on confirmed success).
  // SET BACK TO false BEFORE ANY REAL TESTING OR RELEASE BUILD.
  static const bool _previewAnimationOnly = true;

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
              if (_previewAnimationOnly)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error),
                  ),
                  child: Text(
                    '⚠ PREVIEW MODE — no real payment will happen. Set _previewAnimationOnly = false before real testing.',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
                    textAlign: TextAlign.center,
                  ),
                ),
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
                label: _previewAnimationOnly
                    ? 'Preview Coin Animation'
                    : (vm.paymentInProgress ? 'Confirming payment...' : 'Confirm & Pay ₹${plan.price.toStringAsFixed(0)}'),
                isLoading: !_previewAnimationOnly && (vm.isLoading || vm.paymentInProgress),
                onPressed: () async {
                  if (_previewAnimationOnly) {
                    // Bypasses payAndConfirm() entirely -- no order created,
                    // no Razorpay Checkout opened, no backend call at all.
                    // NOTE: since real gold-crediting now happens via the
                    // backend webhook hook (RechargeService ->
                    // GoldRewardService), this preview path does NOT
                    // increment any real coin count -- it's purely a visual
                    // animation preview. To see the badge update for real,
                    // test with _previewAnimationOnly = false and an actual
                    // successful recharge (one that reaches RECHARGE_SUCCESS,
                    // not just PAYMENT_DONE/REFUNDED).
                    await showGoldCoinReward(
                      ctx,
                      plan.price,
                      onNavigateHome: () => ctx.go(
                        '/dashboard/home',
                        extra: {'justEarnedCoin': true, 'debugBumpCoin': true},
                      ),
                    );
                    return;
                  }

                  final ok = await vm.payAndConfirm();
                  if (!ctx.mounted) return;
                  if (ok) {
                    // Matches backend's GOLD_ELIGIBLE_PLAN_AMOUNT (>= ₹249,
                    // see RechargeService.kt) -- only qualifying recharges
                    // get the coin-toss celebration. Coin crediting itself
                    // happens server-side via the webhook hook -- this just
                    // plays the celebratory animation, it doesn't credit
                    // anything client-side.
                    if (plan.price >= 249) {
                      await showGoldCoinReward(
                        ctx,
                        plan.price,
                        onNavigateHome: () => ctx.go('/dashboard/home', extra: {'justEarnedCoin': true}),
                      );
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