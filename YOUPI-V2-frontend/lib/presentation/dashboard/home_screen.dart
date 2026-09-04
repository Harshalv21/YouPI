import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/coming_soon_overlay.dart';
import '../../core/widgets/shimmer_loader.dart';
import '../../core/widgets/youpi_card.dart';
import '../../data/repositories/recharge_repository.dart';
import '../../data/repositories/gold_repository.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/coin_animation_signal.dart';
import 'home_viewmodel.dart';
import '../recharge/gold_coin_reward_screen.dart';
import '../loan/nbfc_credit_screen.dart';

class HomeScreen extends StatefulWidget {
  final bool justEarnedCoin;
  final bool debugBumpCoin;
  final int? earnedCoins;
  final double? earnedValue;
  const HomeScreen({
    super.key,
    this.justEarnedCoin = false,
    this.debugBumpCoin = false,
    this.earnedCoins,
    this.earnedValue,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _audioPlayer = AudioPlayer();

  bool _showEarnedToast = false;
  Timer? _toastTimer;
  int? _toastCoins;
  double? _toastValue;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeViewModel>().loadHome();
      if (widget.debugBumpCoin) {
        context.read<HomeViewModel>().debugBumpGoldCoinForPreview();
      } else {
        context.read<HomeViewModel>().clearDebugCoinBump();
      }
      if (widget.justEarnedCoin) {
        _audioPlayer.play(AssetSource('sounds/coin_increment.mp3')).catchError((_) {});
      }
      if (widget.justEarnedCoin && widget.earnedCoins != null && widget.earnedValue != null) {
        _toastCoins = widget.earnedCoins;
        _toastValue = widget.earnedValue;
        Future.delayed(const Duration(milliseconds: 250), () {
          if (!mounted) return;
          setState(() => _showEarnedToast = true);
          _toastTimer?.cancel();
          _toastTimer = Timer(const Duration(milliseconds: 3000), () {
            if (!mounted) return;
            setState(() => _showEarnedToast = false);
          });
        });
      }
      _checkPendingCoinAnimation();
      CoinAnimationSignal.tick.addListener(_checkPendingCoinAnimation);
    });
  }

  Future<void> _checkPendingCoinAnimation() async {
    final pending = await StorageService.getPendingCoinAnimation();
    if (pending == null || !mounted) return;

    const maxAttempts = 5;
    const interval = Duration(seconds: 15);
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (!mounted) return;
      try {
        final status = await RechargeRepository().getOrderStatus(pending.orderId);
        if (status.isSuccess) {
          await StorageService.clearPendingCoinAnimation();
          if (!mounted) return;
          final earnedValue = pending.amount * 0.01;
          final earnedCoins = (earnedValue / 0.10).round();
          await showGoldCoinReward(
            context,
            pending.amount,
            onNavigateHome: () {
              if (!mounted) return;
              context.read<HomeViewModel>().loadHome();
              _toastCoins = earnedCoins;
              _toastValue = earnedValue;
              setState(() => _showEarnedToast = true);
              _toastTimer?.cancel();
              _toastTimer = Timer(const Duration(milliseconds: 3000), () {
                if (!mounted) return;
                setState(() => _showEarnedToast = false);
              });
            },
          );
          return;
        }
        if (status.isFailed) {
          await StorageService.clearPendingCoinAnimation();
          return;
        }
      } catch (_) {}
      await Future.delayed(interval);
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _toastTimer?.cancel();
    CoinAnimationSignal.tick.removeListener(_checkPendingCoinAnimation);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeViewModel>(builder: (ctx, vm, _) {
      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        body: Stack(
          children: [
            SafeArea(
              child: vm.isFirstLoad
                  ? const ShimmerList(itemCount: 5, itemHeight: 100)
                  : RefreshIndicator(
                color: AppColors.primary,
                backgroundColor: AppColors.backgroundCard,
                onRefresh: vm.loadHome,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppDimensions.paddingPage),
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (vm.isShowingMockProfile)
                        Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.error.withOpacity(0.4)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Could not load your real profile -- showing placeholder data. Pull to refresh to retry.',
                                style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
                              ),
                            ),
                          ]),
                        ),
                      // Header
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    vm.isGuest
                                        ? 'Welcome, Guest! 👋'
                                        : 'Welcome back, ${vm.user.name.split(' ').first}! 👋',
                                    style: AppTextStyles.headlineMedium),
                                Text(
                                    vm.isGuest
                                        ? 'Register to unlock your full account.'
                                        : 'Your financial snapshot is ready.',
                                    style: AppTextStyles.bodySmall),
                              ],
                            ),
                          ),
                          _GoldRewardCoin(
                            amount: _goldRewardBalance(vm),
                            coinCount: _goldCoinCount(vm),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      // ── CREDIT LIMIT CARD ──────────────────────────
                      // Replaces the old Wallet/Total Balance card on Home.
                      // TODO: wire creditLimit / freeAmount / paidAmount /
                      // nbfcName / isActive to real fields on HomeViewModel
                      // once the Dikshi Finlease sanction API response is
                      // exposed here (see YouPi Credit / SmartSave NBFC
                      // architecture docs) -- values below are placeholders
                      // matching the design mock until that's wired.
                      const _CreditLimitCard(
                        creditLimit: 10000,
                        freeAmount: 2000,
                        paidAmount: 8000,
                        nbfcName: 'DreamFin NBFC',
                        isActive: true,
                      ),

                      const SizedBox(height: 24),
                      // Quick actions
                      Text('Quick Actions', style: AppTextStyles.headlineSmall),
                      // Quick actions
                      const SizedBox(height: 12),

// ═══════════════════════════════════════════════════════════
// ASSUMPTION TO CONFIRM: this uses vm.user.isKycVerified (matches
// UserProfileResponse.isKycVerified on the backend, and UserModel already
// has an isKycVerified field per user_repository.dart's getProfile()
// parsing). If HomeViewModel's user model field is named differently,
// the condition needs a one-word adjustment.
// ═══════════════════════════════════════════════════════════
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 90,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _QuickAction('Recharge', Icons.wifi_rounded, () => ctx.go('/dashboard/plans')),
                            _QuickAction('Smart Saver', Icons.savings_rounded, () => ctx.push('/plans/smartsave'), locked: true),
                            _QuickAction('Wallet', Icons.account_balance_wallet_rounded, () => ctx.go('/dashboard/wallet')),
                            _QuickAction('Gold', Icons.monetization_on_rounded, () => ctx.push('/invest/gold'), ),
                            _QuickAction('FD Invest', Icons.trending_up_rounded, () => ctx.push('/invest/fd'), ),
                            _QuickAction('BNPL Shop', Icons.credit_card_rounded, () => ctx.go('/dashboard/bnpl'), locked: true),
                            _QuickAction('Credit', Icons.account_balance_rounded, () => ctx.push('/loan/nbfc-credit')),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Portfolio
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('My Portfolio', style: AppTextStyles.headlineSmall),
                          TextButton(
                            onPressed: null,
                            child: Text('View all',
                                style: AppTextStyles.tealLink.copyWith(
                                  decoration: TextDecoration.none,
                                  color: AppColors.textSecondary,
                                )),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _PortfolioMetric('Digital Gold',
                              CurrencyFormatter.format(vm.user.goldBalanceGrams * 6842), AppColors.secondary),
                          const SizedBox(width: 12),
                          _PortfolioMetric('FD Return', '7.5% p.a.', AppColors.primary, locked: true),
                          const SizedBox(width: 12),
                          _PortfolioMetric('BNPL Limit',
                              CurrencyFormatter.formatNoDecimal(vm.user.bnplLimit - vm.user.bnplUsed), AppColors.primary,
                              locked: true),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Bills & recharges
                      Text('Bills & Recharges', style: AppTextStyles.headlineSmall),
                      const SizedBox(height: 12),
                      GridView.count(
                        crossAxisCount: 4,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 8,
                        childAspectRatio: 0.85,
                        children: [
                          _BillTile('Mobile\nRecharge', Icons.smartphone_rounded, () => ctx.go('/dashboard/plans')),
                          _BillTile('Postpaid', Icons.receipt_long_rounded, () {}, locked: true),
                          _BillTile('DTH /\nCable TV', Icons.live_tv_rounded, () => ctx.push('/dth/operator-select')),
                          _BillTile('Electricity', Icons.bolt_rounded, () {}, locked: true),
                          _BillTile('Credit\nCards', Icons.credit_card_rounded, () {}, locked: true),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Active recharge
                      Text('Active Recharge', style: AppTextStyles.headlineSmall),
                      const SizedBox(height: 12),
                      vm.activeRecharges.isEmpty
                          ? YoupiCard(
                        child: Column(
                          children: [
                            const Icon(Icons.wifi_off_rounded, color: AppColors.textSecondary, size: 28),
                            const SizedBox(height: 8),
                            Text('No Active Recharge', style: AppTextStyles.labelLarge),
                            const SizedBox(height: 4),
                            Text('Recharge now to see your plan here',
                                style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: () => ctx.go('/dashboard/plans'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: AppColors.primary),
                                ),
                                child: Text('Recharge Now',
                                    style: AppTextStyles.chipText.copyWith(color: AppColors.primary)),
                              ),
                            ),
                          ],
                        ),
                      )
                          : vm.activeRecharges.length == 1
                          ? _ActiveRechargeCard(vm.activeRecharges.first)
                          : SizedBox(
                        height: 132,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: vm.activeRecharges.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (ctx, i) => SizedBox(
                            width: MediaQuery.of(ctx).size.width - (AppDimensions.paddingPage * 2) - 40,
                            child: _ActiveRechargeCard(vm.activeRecharges[i]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Special offers
                      Text('Special Offers', style: AppTextStyles.headlineSmall),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 120,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: vm.offers.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (ctx, i) {
                            final offer = vm.offers[i];
                            final isLocked = (offer['title'] ?? '')
                                .toLowerCase()
                                .contains('bnpl boost');
                            return _OfferCard(offer, locked: isLocked);
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
            if (_toastCoins != null && _toastValue != null)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: _GoldCoinEarnedToast(
                    visible: _showEarnedToast,
                    coins: _toastCoins!,
                    value: _toastValue!,
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }

  double _goldRewardBalance(HomeViewModel vm) => vm.goldBalanceRupees;

  int _goldCoinCount(HomeViewModel vm) => vm.goldCoinCount;
}

/// ── Credit Limit card ──────────────────────────────────────────────
/// Shown at the top of Home in place of the old wallet balance card.
/// Displays the NBFC-sanctioned credit limit with the Free/Paid (20/80)
/// split as a progress bar, matching the SmartSave/YouPi Credit design.
class _CreditLimitCard extends StatelessWidget {
  final double creditLimit;
  final double freeAmount;
  final double paidAmount;
  final String nbfcName;
  final bool isActive;

  const _CreditLimitCard({
    required this.creditLimit,
    required this.freeAmount,
    required this.paidAmount,
    required this.nbfcName,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    final freeRatio = creditLimit > 0 ? (freeAmount / creditLimit).clamp(0.0, 1.0) : 0.0;
    final freePct = (freeRatio * 100).round();
    final paidPct = 100 - freePct;

    return GestureDetector(
      onTap: () => context.push('/loan/nbfc-credit'),
      child: YoupiGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Your credit limit', style: AppTextStyles.labelMedium),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                CurrencyFormatter.formatNoDecimal(creditLimit),
                style: AppTextStyles.amountLarge,
              ),
              const SizedBox(width: 10),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Active',
                    style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Sanctioned by $nbfcName',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Row(
              children: [
                Expanded(
                  flex: freePct,
                  child: Container(height: 8, color: AppColors.primary),
                ),
                Expanded(
                  flex: paidPct,
                  child: Container(height: 8, color: AppColors.secondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _CreditLimitLegend(
                  color: AppColors.primary,
                  label: 'Free ($freePct%)',
                  amount: CurrencyFormatter.formatNoDecimal(freeAmount),
                  sublabel: 'Interest free',
                ),
              ),
              Expanded(
                child: _CreditLimitLegend(
                  color: AppColors.secondary,
                  label: 'Paid ($paidPct%)',
                  amount: CurrencyFormatter.formatNoDecimal(paidAmount),
                  sublabel: 'Interest applicable',
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

class _CreditLimitLegend extends StatelessWidget {
  final Color color;
  final String label;
  final String amount;
  final String sublabel;
  const _CreditLimitLegend({
    required this.color,
    required this.label,
    required this.amount,
    required this.sublabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(label, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
          ],
        ),
        const SizedBox(height: 4),
        Text(amount, style: AppTextStyles.labelLarge),
        Text(sublabel, style: AppTextStyles.captionText.copyWith(color: AppColors.textSecondary)),
      ],
    );
  }
}

/// Small auto-dismissing banner shown near the top of Home right after a
/// successful recharge -- "You earned N YouPi Coins!" / "Worth ₹X".
class _GoldCoinEarnedToast extends StatelessWidget {
  final bool visible;
  final int coins;
  final double value;
  const _GoldCoinEarnedToast({
    required this.visible,
    required this.coins,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 380),
        curve: visible ? Curves.easeOutBack : Curves.easeInCubic,
        offset: visible ? Offset.zero : const Offset(0, -1.4),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: visible ? 1.0 : 0.0,
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.backgroundCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.secondary.withOpacity(0.6)),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.secondary.withOpacity(0.25),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'You earned $coins YouPi Coin${coins == 1 ? '' : 's'}!',
                    style: AppTextStyles.labelLarge.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.secondary.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Worth ₹${value.toStringAsFixed(2)}',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.textSecondary.withOpacity(0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GoldRewardCoin extends StatelessWidget {
  final double amount;
  final int coinCount;
  const _GoldRewardCoin({required this.amount, required this.coinCount});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        barrierColor: Colors.black87,
        builder: (_) => _GoldRewardPopup(amount: amount, coinCount: coinCount),
      ),
      child: SizedBox(
        width: 64,
        height: 64,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Image.asset(
              'assets/images/youpi_coin.png',
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) =>
              const Icon(Icons.monetization_on_rounded, color: AppColors.secondary, size: 36),
            ),
            if (coinCount > 0)
              Positioned(
                top: -2,
                right: -2,
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(coinCount),
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutBack,
                  builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    constraints: const BoxConstraints(minWidth: 20),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.backgroundPrimary, width: 2),
                    ),
                    child: Text(
                      coinCount > 99 ? '99+' : '$coinCount',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GoldRewardPopup extends StatefulWidget {
  final double amount;
  final int coinCount;
  const _GoldRewardPopup({required this.amount, required this.coinCount});

  @override
  State<_GoldRewardPopup> createState() => _GoldRewardPopupState();
}

class _GoldRewardPopupState extends State<_GoldRewardPopup> {
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.backgroundCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
        side: BorderSide(color: AppColors.secondary.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 112,
              height: 112,
              child: Image.asset(
                'assets/images/youpi_coin.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                const Icon(Icons.monetization_on_rounded, color: AppColors.secondary, size: 64),
              ),
            ),
            const SizedBox(height: 14),
            Text('Gold Reward', style: AppTextStyles.headlineSmall),
            const SizedBox(height: 6),
            Text(
              'Earn 4% of every recharge as YouPi Coins',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${widget.coinCount} Coin${widget.coinCount == 1 ? '' : 's'}',
                maxLines: 1,
                style: AppTextStyles.amountLarge.copyWith(color: AppColors.secondary),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Worth ${CurrencyFormatter.format(widget.amount)}',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => ComingSoonOverlay.showComingSoonTopBanner(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Withdraw', style: AppTextStyles.labelLarge.copyWith(color: Colors.black)),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActiveRechargeCard extends StatelessWidget {
  final ActiveRechargeResult recharge;
  const _ActiveRechargeCard(this.recharge);

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  String _formatDate(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';

  @override
  Widget build(BuildContext context) {
    final expiringSoon = recharge.daysRemaining <= 3;
    return YoupiCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.wifi_rounded, color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${recharge.operator.toUpperCase()} • ₹${recharge.planAmount.toStringAsFixed(0)}',
                        style: AppTextStyles.labelLarge),
                    Text(recharge.mobileNumber, style: AppTextStyles.bodySmall),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (expiringSoon ? AppColors.error : AppColors.primary).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  recharge.daysRemaining == 0 ? 'Expires today' : '${recharge.daysRemaining}d left',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: expiringSoon ? AppColors.error : AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Active till ${_formatDate(recharge.expiryDate)}', style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }
}

class _BillTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool locked;
  final GlobalKey<ComingSoonOverlayState> _comingSoonKey = GlobalKey();

  _BillTile(this.label, this.icon, this.onTap, {this.locked = false});

  @override
  Widget build(BuildContext context) {
    final iconSquare = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Icon(icon, color: AppColors.primary, size: 22),
    );

    return GestureDetector(
      onTap: locked
          ? () {
        _comingSoonKey.currentState?.triggerFastBlink();
        ComingSoonOverlay.showComingSoonSnack(context);
      }
          : onTap,
      child: Column(
        children: [
          locked
              ? ComingSoonOverlay(
              key: _comingSoonKey,
              shape: BoxShape.rectangle, showLabel: true, iconSize: 16, interactive: false, child: iconSquare)
              : iconSquare,
          const SizedBox(height: 6),
          Text(label, style: AppTextStyles.labelSmall, textAlign: TextAlign.center, maxLines: 2),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool locked;
  final GlobalKey<ComingSoonOverlayState> _comingSoonKey = GlobalKey();

  _QuickAction(this.label, this.icon, this.onTap, {this.locked = false});

  @override
  Widget build(BuildContext context) {
    final iconCircle = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.divider),
      ),
      child: Icon(icon, color: AppColors.primary, size: 22),
    );

    return GestureDetector(
      onTap: locked
          ? () {
        _comingSoonKey.currentState?.triggerFastBlink();
        ComingSoonOverlay.showComingSoonSnack(context);
      }
          : onTap,
      child: Container(
        width: 72,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            locked
                ? ComingSoonOverlay(
                key: _comingSoonKey,
                shape: BoxShape.circle, showLabel: true, iconSize: 18, interactive: false, child: iconCircle)
                : iconCircle,
            const SizedBox(height: 6),
            Text(label, style: AppTextStyles.labelSmall, textAlign: TextAlign.center, maxLines: 2),
          ],
        ),
      ),
    );
  }
}

class _PortfolioMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool locked;
  const _PortfolioMetric(this.label, this.value, this.color, {this.locked = false});

  @override
  Widget build(BuildContext context) {
    final card = YoupiCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.labelSmall),
          const SizedBox(height: 4),
          Text(value, style: AppTextStyles.labelLarge.copyWith(color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
    return Expanded(
      child: locked
          ? ComingSoonOverlay(
        iconSize: 16,
        showLabel: true,
        labelFontSize: 10,
        child: card,
      )
          : card,
    );
  }
}

class _OfferCard extends StatelessWidget {
  final Map<String, String> offer;
  final bool locked;
  const _OfferCard(this.offer, {this.locked = false});

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.backgroundCard, AppColors.backgroundSurface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(offer['tag'] ?? '', style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary)),
          ),
          const SizedBox(height: 6),
          Text(offer['title'] ?? '', style: AppTextStyles.labelLarge),
          Text(offer['subtitle'] ?? '', style: AppTextStyles.captionText, maxLines: 2),
        ],
      ),
    );

    if (!locked) return card;
    return ComingSoonOverlay(iconSize: 16, showLabel: true, labelFontSize: 12, child: card);
  }
}