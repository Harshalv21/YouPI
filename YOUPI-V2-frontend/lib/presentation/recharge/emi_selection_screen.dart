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

  // ── Metadata for whichever mode is currently selected -- powers the
  // collapsed "Select payment method" row's icon/title/subtitle. ──
  ({IconData? icon, String? imageAsset, String title, String subtitle}) _modeMeta(
    RechargeViewModel vm,
    double planPrice,
  ) {
    switch (vm.paymentMode) {
      case 'WALLET':
        return (
          icon: Icons.account_balance_wallet_rounded,
          imageAsset: null,
          title: 'Wallet',
          subtitle: _walletLoading
              ? 'Checking balance...'
              : (_walletBalance == null
                  ? 'Balance unavailable'
                  : 'Balance: ₹${_walletBalance!.toStringAsFixed(0)}'),
        );
      case 'SPLIT':
        return (
          icon: Icons.call_split_rounded,
          imageAsset: null,
          title: 'Wallet + Gateway',
          subtitle:
              '₹${(_walletBalance ?? 0).toStringAsFixed(0)} from wallet + ₹${(planPrice - (_walletBalance ?? 0)).toStringAsFixed(0)} via UPI/Card',
        );
      default:
        return (
          icon: Icons.qr_code_scanner_rounded,
          imageAsset: null,
          title: 'Pay via Gateway',
          subtitle: 'UPI, Cards, NetBanking via Razorpay',
        );
    }
  }

  // ── Consent dialog for WALLET / SPLIT -- Pay button seedha payment
  // trigger nahi karta in dono modes ke liye; pehle explicit confirm
  // lena zaroori hai ki wallet se paisa kat raha hai. Returns true only
  // if the user tapped Confirm.
  Future<bool> _confirmWalletDebit({
    required BuildContext context,
    required RechargeViewModel vm,
    required double planPrice,
  }) async {
    final isSplit = vm.paymentMode == 'SPLIT';
    final walletPortion = isSplit ? (_walletBalance ?? 0) : planPrice;
    final gatewayPortion = isSplit ? (planPrice - (_walletBalance ?? 0)) : 0.0;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.backgroundCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Confirm payment', style: AppTextStyles.headlineSmall),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isSplit)
              Text(
                '₹${walletPortion.toStringAsFixed(0)} will be debited from your Wallet for this recharge.',
                style: AppTextStyles.bodyMedium,
              )
            else ...[
              Text(
                'This recharge will be paid using:',
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('From Wallet', style: AppTextStyles.bodySmall),
                  Text('₹${walletPortion.toStringAsFixed(0)}',
                      style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Via UPI/Card', style: AppTextStyles.bodySmall),
                  Text('₹${gatewayPortion.toStringAsFixed(0)}',
                      style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'This amount is non-refundable once the recharge is successful.',
              style: AppTextStyles.captionText.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text('Cancel', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text('Confirm & Pay', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _openPaymentMethodSheet({
    required BuildContext context,
    required RechargeViewModel vm,
    required bool walletPartial,
    required bool walletSufficient,
    required double planPrice,
  }) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.backgroundCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppColors.textSecondary.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Text('Select payment method', style: AppTextStyles.headlineSmall),
                const SizedBox(height: 16),

                _PaymentModeOption(
                  icon: Icons.account_balance_wallet_rounded,
                  iconColor: AppColors.primary,
                  title: 'Wallet',
                  subtitle: _walletLoading
                      ? 'Checking balance...'
                      : (_walletBalance == null
                          ? 'Balance unavailable'
                          : 'Balance: ₹${_walletBalance!.toStringAsFixed(0)}'),
                  selected: vm.paymentMode == 'WALLET',
                  enabled: !_walletLoading,
                  onTap: () {
                    vm.selectWalletPayment();
                    Navigator.pop(sheetCtx);
                  },
                ),

                if (vm.paymentMode == 'WALLET' && !_walletLoading && !walletSufficient)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      'Insufficient wallet balance. You need ₹${(planPrice - (_walletBalance ?? 0)).toStringAsFixed(0)} more.',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
                      textAlign: TextAlign.center,
                    ),
                  ),

                if (walletPartial) ...[
                  const SizedBox(height: 10),
                  _PaymentModeOption(
                    icon: Icons.call_split_rounded,
                    iconColor: AppColors.primary,
                    title: 'Wallet + Gateway',
                    subtitle:
                        '₹${_walletBalance!.toStringAsFixed(0)} from wallet + ₹${(planPrice - _walletBalance!).toStringAsFixed(0)} via UPI/Card',
                    selected: vm.paymentMode == 'SPLIT',
                    enabled: true,
                    onTap: () {
                      vm.selectSplitPayment();
                      vm.setSplitWalletAmount(_walletBalance!);
                      Navigator.pop(sheetCtx);
                    },
                  ),
                ],

                const SizedBox(height: 10),
                _PaymentModeOption(
                  icon: Icons.qr_code_scanner_rounded,
                  iconColor: AppColors.primary,
                  title: 'Pay via Gateway',
                  subtitle: 'UPI, Cards, NetBanking via Razorpay',
                  selected: vm.paymentMode == 'FULL',
                  enabled: true,
                  onTap: () {
                    vm.selectFullPayment();
                    Navigator.pop(sheetCtx);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RechargeViewModel>(builder: (ctx, vm, _) {
      final plan = vm.selectedPlan;
      if (plan == null) return const Scaffold(body: Center(child: Text('No plan selected')));

      final walletSufficient = _walletBalance != null && _walletBalance! >= plan.price;
      // ← partial balance hai (0 se zyada, lekin plan price se kam) --
      // tabhi SPLIT option dikhega.
      final walletPartial = _walletBalance != null && _walletBalance! > 0 && !walletSufficient;
      final meta = _modeMeta(vm, plan.price);

      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(backgroundColor: AppColors.backgroundPrimary,
            title: Text('Confirm Recharge', style: AppTextStyles.headlineMedium)),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
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
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(plan.name, style: AppTextStyles.headlineSmall),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(plan.operator.toUpperCase(),
                                    style: AppTextStyles.labelSmall.copyWith(
                                        color: AppColors.primary, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(Icons.sim_card_rounded, size: 14, color: AppColors.textSecondary),
                              const SizedBox(width: 4),
                              Text('${plan.dataPerDay}/day', style: AppTextStyles.bodySmall),
                              const SizedBox(width: 14),
                              Icon(Icons.calendar_month_rounded, size: 14, color: AppColors.textSecondary),
                              const SizedBox(width: 4),
                              Text('${plan.validityDays} days', style: AppTextStyles.bodySmall),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Divider(color: AppColors.textSecondary.withOpacity(0.15), height: 1),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text('Total amount',
                                  style: AppTextStyles.captionText.copyWith(color: AppColors.textSecondary)),
                              Text('₹${plan.price.toStringAsFixed(0)}',
                                  style: AppTextStyles.amountMedium.copyWith(color: AppColors.primary)),
                            ],
                          ),
                        ]),
                      ),

                      // ← SPLIT consent breakdown -- explicit dikhata hai ki
                      // kitna wallet se aur kitna gateway se katega, "Pay"
                      // dabane se pehle. Method-selector se upar dikhta hai
                      // taaki scroll karke bina sheet khole bhi dikh jaye.
                      if (vm.paymentMode == 'SPLIT')
                        Container(
                          margin: const EdgeInsets.only(top: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Payment breakdown',
                                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.textSecondary)),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('From Wallet', style: AppTextStyles.bodySmall),
                                  Text('₹${(_walletBalance ?? 0).toStringAsFixed(0)}',
                                      style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Via UPI/Card', style: AppTextStyles.bodySmall),
                                  Text('₹${(plan.price - (_walletBalance ?? 0)).toStringAsFixed(0)}',
                                      style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ],
                          ),
                        ),

                    ],
                  ),
                ),
              ),

              // ── Bottom sheet-style payment method selector, docked at
              // the bottom like native UPI/Razorpay checkout screens. ──
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimensions.paddingPage, 8, AppDimensions.paddingPage, 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Select payment method',
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 8),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: (_walletLoading) ? null : () => _openPaymentMethodSheet(
                        context: ctx,
                        vm: vm,
                        walletPartial: walletPartial,
                        walletSufficient: walletSufficient,
                        planPrice: plan.price,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 1.2),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              padding: meta.imageAsset != null ? const EdgeInsets.all(9) : EdgeInsets.zero,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: meta.imageAsset != null
                                  ? Image.asset(meta.imageAsset!, fit: BoxFit.contain)
                                  : Icon(meta.icon, color: AppColors.primary, size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(meta.title,
                                      style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 2),
                                  Text(meta.subtitle,
                                      style: AppTextStyles.captionText,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                            Icon(Icons.keyboard_arrow_down_rounded,
                                color: AppColors.textSecondary, size: 24),
                          ],
                        ),
                      ),
                    ),

                    // ← Insufficient-wallet-balance warning ab yaha, selector
                    // ke turant neeche hai -- pehle ye plan-card ke upar tha
                    // jo scroll area mein akela dikhta tha aur beech mein bada
                    // khaali gap bana deta tha. Ab context (selector + Pay
                    // button) ke saath docked hai, gap nahi dikhta.
                    if (vm.paymentMode == 'WALLET' && !_walletLoading && !walletSufficient)
                      Container(
                        margin: const EdgeInsets.only(top: 10),
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

                    const SizedBox(height: 14),
                    YoupiButton(
                      label: _previewAnimationOnly
                          ? 'Preview Coin Animation'
                          : (vm.paymentInProgress ? 'Confirming payment...' : 'Pay ₹${plan.price.toStringAsFixed(0)}'),
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

                        // ← Consent gate: WALLET/SPLIT dono explicit
                        // confirm maangte hai ki wallet se paisa kat raha
                        // hai, "Confirm & Pay" tap na ho to yahi ruk jaata
                        // hai -- payAndConfirm() call hi nahi hota.
                        if (vm.paymentMode == 'WALLET' || vm.paymentMode == 'SPLIT') {
                          final consented = await _confirmWalletDebit(
                            context: ctx,
                            vm: vm,
                            planPrice: plan.price,
                          );
                          if (!consented || !ctx.mounted) return;
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
                        } else {
                          // ← Safety net: agar ok==false lekin na error set
                          // hua na stillProcessing -- pehle silently kuch
                          // nahi hota tha. Ab kam se kam user ko pata chale
                          // ki kuch gadbad hui, screen pe atka na rahe.
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('Something went wrong confirming your recharge. Please check My Recharges.'),
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

/// GPay/PhonePe-style payment method row used inside the bottom sheet:
/// leading icon chip on the left, title + subtitle in the middle,
/// and a trailing check-circle that only appears when selected.
class _PaymentModeOption extends StatelessWidget {
  final IconData? icon;
  final String? imageAsset;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _PaymentModeOption({
    this.icon,
    this.imageAsset,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    required this.onTap,
  }) : assert(icon != null || imageAsset != null, 'Provide either icon or imageAsset');

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.backgroundPrimary,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.backgroundPrimary,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                padding: imageAsset != null ? const EdgeInsets.all(9) : EdgeInsets.zero,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: imageAsset != null
                    ? Image.asset(imageAsset!, fit: BoxFit.contain)
                    : Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: AppTextStyles.captionText),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: selected
                    ? Container(
                        key: const ValueKey('checked'),
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check, size: 15, color: Colors.black),
                      )
                    : Container(
                        key: const ValueKey('unchecked'),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.textSecondary.withOpacity(0.5), width: 1.5),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}