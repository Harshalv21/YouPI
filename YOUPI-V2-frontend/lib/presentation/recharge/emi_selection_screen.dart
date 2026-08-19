import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_card.dart';
import '../../data/repositories/wallet_repository.dart';
import 'gold_coin_reward_screen.dart';
import 'recharge_viewmodel.dart';

class EmiSelectionScreen extends StatefulWidget {
  const EmiSelectionScreen({super.key});

  @override
  State<EmiSelectionScreen> createState() => _EmiSelectionScreenState();
}

class _EmiSelectionScreenState extends State<EmiSelectionScreen> {
  static const bool _previewAnimationOnly = false;

  final WalletRepository _walletRepo = WalletRepository();
  double? _walletBalance;
  bool _walletLoading = true;

  @override
  void initState() {
    super.initState();
    // Default to FULL every time this screen opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RechargeViewModel>().selectFullPayment();
    });
    _loadWalletBalance();
  }

  Future<void> _loadWalletBalance() async {
    try {
      final bal = await _walletRepo.getNbfcBalance();
      if (mounted) setState(() { _walletBalance = bal; _walletLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _walletLoading = false; });
    }
  }

  double _valueForAmount(double rechargeAmount) => rechargeAmount * 0.01;
  int _coinsForAmount(double rechargeAmount) =>
      (_valueForAmount(rechargeAmount) / 0.10).round();

  @override
  Widget build(BuildContext context) {
    return Consumer<RechargeViewModel>(builder: (ctx, vm, _) {
      final plan = vm.selectedPlan;
      if (plan == null) return const Scaffold(body: Center(child: Text('No plan selected')));

      final walletSufficient = _walletBalance != null && _walletBalance! >= plan.price;

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
              const SizedBox(height: 20),

              // ── Payment method selector ──
              Text('Pay using', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              _PaymentModeOption(
                title: 'Wallet',
                subtitle: _walletLoading
                    ? 'Checking balance...'
                    : (_walletBalance == null
                        ? 'Balance unavailable'
                        : 'Balance: ₹${_walletBalance!.toStringAsFixed(0)}'),
                selected: vm.paymentMode == 'WALLET',
                // ← Wallet hamesha selectable rahegi, chahe balance 0 ho ya
                // kam ho -- sirf loading state mein disable hoti hai.
                enabled: !_walletLoading,
                onTap: () => vm.selectWalletPayment(),
              ),

              // ← Turant dikhta hai jaise hi Wallet select ho aur balance
              // kam ho -- Pay button dabane ka wait nahi karna padta.
              if (vm.paymentMode == 'WALLET' && !_walletLoading && !walletSufficient)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Insufficient wallet balance. You need ₹${(plan.price - (_walletBalance ?? 0)).toStringAsFixed(0)} more.',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      YoupiButton(
                        label: 'Add Money to Wallet',
                        onPressed: () => ctx.push('/wallet/add'),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 10),
              _PaymentModeOption(
                title: 'Pay via Gateway',
                subtitle: 'UPI, Cards, NetBanking via Razorpay',
                selected: vm.paymentMode == 'FULL',
                enabled: true,
                onTap: () => vm.selectFullPayment(),
              ),

              const SizedBox(height: 20),
              YoupiButton(
                label: _previewAnimationOnly
                    ? 'Preview Coin Animation'
                    : (vm.paymentInProgress ? 'Confirming payment...' : 'Confirm & Pay ₹${plan.price.toStringAsFixed(0)}'),
                isLoading: !_previewAnimationOnly && (vm.isLoading || vm.paymentInProgress),
                onPressed: (vm.paymentMode == 'WALLET' && !walletSufficient) ? null : () async {
                  if (_previewAnimationOnly) {
                    await showGoldCoinReward(
                      ctx,
                      plan.price,
                      onNavigateHome: () => ctx.go(
                        '/dashboard/home',
                        extra: {
                          'justEarnedCoin': true,
                          'debugBumpCoin': true,
                          'earnedCoins': _coinsForAmount(plan.price),
                          'earnedValue': _valueForAmount(plan.price),
                        },
                      ),
                    );
                    return;
                  }

                  final ok = await vm.payAndConfirm();
                  if (!ctx.mounted) return;
                  if (ok) {
                    if (plan.price >= 249) {
                      await showGoldCoinReward(
                        ctx,
                        plan.price,
                        onNavigateHome: () => ctx.go(
                          '/dashboard/home',
                          extra: {
                            'justEarnedCoin': true,
                            'earnedCoins': _coinsForAmount(plan.price),
                            'earnedValue': _valueForAmount(plan.price),
                          },
                        ),
                      );
                    } else {
                      ctx.go('/plans/success');
                    }
                  } else if (vm.stillProcessing) {
                    ctx.go('/dashboard/home');
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(vm.error ?? 'Payment received — confirming your recharge.'),
                        backgroundColor: AppColors.backgroundCard,
                      ),
                    );
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

class _PaymentModeOption extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _PaymentModeOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.backgroundCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primary : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.bodyMedium),
                    Text(subtitle, style: AppTextStyles.captionText),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}