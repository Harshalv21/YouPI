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

class HomeScreen extends StatefulWidget {
  // Set true only when navigated here right after a qualifying recharge
  // (see emi_selection_screen.dart) -- lets this screen play the
  // coin-collect sound exactly once, on that specific arrival. Does NOT
  // control what number is shown -- that always comes from the real
  // backend-connected HomeViewModel.goldCoinCount/goldBalanceRupees.
  final bool justEarnedCoin;
  // DEBUG-ONLY -- set true only from the PREVIEW-mode branch in
  // emi_selection_screen.dart. Triggers a fake, in-memory-only badge
  // increment (see HomeViewModel.debugBumpGoldCoinForPreview) so the pop
  // animation can be tested while the real gold_wallet table is empty.
  // Never set this from the real payment path.
  final bool debugBumpCoin;
  // Real coin count / rupee value earned on THIS specific recharge -- passed
  // from emi_selection_screen.dart so the auto-toast below can show the
  // correct numbers for what was just credited, instead of the running
  // total shown in the header coin badge/popup. Null when justEarnedCoin is
  // false (nothing to show).
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
  bool _balanceHidden = true;
  final _audioPlayer = AudioPlayer();

  // Auto-toast ("You earned N YouPi Coins! Worth ₹X") shown for a few
  // seconds right when Home is first reached after a successful recharge --
  // separate from the header badge pop-in, which stays permanently updated.
  bool _showEarnedToast = false;
  Timer? _toastTimer;
  // Mutable so the async follow-up check (_checkPendingCoinAnimation) can
  // populate these too -- widget.earnedCoins/earnedValue only exist when
  // Home was reached via a fresh navigation right after a recharge; the
  // async path resolves later, with Home already sitting there, so it has
  // no route params to read from and needs its own place to put the numbers.
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
        // Guards against a stale preview-test number masking a real
        // credit later in the same app session (see clearDebugCoinBump
        // doc comment in home_viewmodel.dart).
        context.read<HomeViewModel>().clearDebugCoinBump();
      }
      if (widget.justEarnedCoin) {
        // Fire-and-forget -- never let a sound failure affect the actual
        // screen/data loading above.
        _audioPlayer.play(AssetSource('sounds/coin_increment.mp3')).catchError((_) {});
      }
      // Only show the toast when we actually have real numbers to show --
      // (earnedCoins/earnedValue are null if, e.g., a route was reached
      // with justEarnedCoin=true but no numbers were passed).
      if (widget.justEarnedCoin && widget.earnedCoins != null && widget.earnedValue != null) {
        _toastCoins = widget.earnedCoins;
        _toastValue = widget.earnedValue;
        // Small delay so the toast slides in just after the coin-fly
        // overlay (gold_coin_reward_screen.dart) finishes landing on the
        // header badge -- feels like a continuation, not two things
        // fighting for attention at once.
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
      // Push notification arriving while Home is already open/foregrounded
      // (see push_notification_service.dart) fires this signal instead of
      // relying on initState, since navigating to an already-mounted route
      // doesn't re-run it.
      CoinAnimationSignal.tick.addListener(_checkPendingCoinAnimation);
    });
  }

  // Async follow-up for a recharge whose PAYMENT succeeded but fulfillment
  // hadn't confirmed by the time emi_selection_screen.dart's synchronous
  // polling window ran out (see recharge_viewmodel.dart's _stillProcessing
  // and _pollOrderStatus). Rather than the animation being lost entirely,
  // Home rechecks the order here -- however long after the original
  // recharge attempt this turns out to be -- and plays the SAME reward
  // animation + toast the moment it actually resolves to success.
  //
  // Bounded to 5 checks, 15s apart (75s of additional runway on top of the
  // 50s already spent synchronously) WHILE this Home screen instance stays
  // mounted. If it's still unresolved after that, the pending record is
  // left in storage (not cleared) so the NEXT time Home loads -- even a
  // fresh app open -- it tries again from scratch. Only a confirmed
  // success or failure clears it for good.
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
            // Already on Home -- no route change needed, just show the
            // same toast the normal (synchronous) path shows.
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
          // Genuinely failed -- nothing to animate, stop checking this one.
          await StorageService.clearPendingCoinAnimation();
          return;
        }
      } catch (_) {
        // Transient network hiccup -- just try again next tick.
      }
      await Future.delayed(interval);
    }
    // Still unresolved after 75s -- leave the pending record in place for
    // the next Home load to pick up again.
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
                          // YouPi Gold Coin -- replaces the old notification bell.
                          // Now wired to the REAL backend (GoldRepository via
                          // HomeViewModel.goldCoinCount/goldBalanceRupees) --
                          // no longer a local stand-in.
                          _GoldRewardCoin(
                            amount: _goldRewardBalance(vm),
                            coinCount: _goldCoinCount(vm),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ComingSoonOverlay(
                        iconSize: 26,
                        labelFontSize: 13,
                        labelAlignment: const Alignment(0.55, -0.75),
                        child: YoupiGlassCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Total Balance', style: AppTextStyles.labelMedium),
                                  GestureDetector(
                                    onTap: () => setState(() => _balanceHidden = !_balanceHidden),
                                    child: Icon(
                                      _balanceHidden ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                      color: AppColors.textSecondary,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _balanceHidden ? '₹ • • • • • •' : CurrencyFormatter.format(vm.walletBalance),
                                style: AppTextStyles.amountLarge,
                              ),
                              const SizedBox(height: 12),
                              Align(
                                alignment: Alignment.centerRight,
                                child: GestureDetector(
                                  onTap: () => context.go('/dashboard/wallet'),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: AppColors.primary),
                                    ),
                                    child: Text('View Wallet',
                                        style: AppTextStyles.chipText.copyWith(color: AppColors.primary)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Quick actions
                      Text('Quick Actions', style: AppTextStyles.headlineSmall),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 90,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            _QuickAction('Recharge', Icons.wifi_rounded, () => ctx.go('/dashboard/plans')),
                            _QuickAction('Smart Saver', Icons.savings_rounded, () => ctx.push('/plans/smartsave'), locked: true),
                            _QuickAction('Wallet', Icons.account_balance_wallet_rounded, () => ctx.go('/dashboard/wallet'), locked: true),
                            _QuickAction('Gold', Icons.monetization_on_rounded, () => ctx.push('/invest/gold'), locked: true),
                            _QuickAction('FD Invest', Icons.trending_up_rounded, () => ctx.push('/invest/fd'), locked: true),
                            _QuickAction('BNPL Shop', Icons.credit_card_rounded, () => ctx.go('/dashboard/bnpl'), locked: true),
                            _QuickAction('Loan', Icons.account_balance_rounded, () => ctx.push('/loan/apply/step1'), locked: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      // Portfolio
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('My Portfolio', style: AppTextStyles.headlineSmall),
                          // Disabled: Portfolio view isn't ready yet (teammate's
                          // change). onPressed: null makes it visually dull and
                          // non-interactive automatically -- no separate locked/
                          // onTap check needed like the ComingSoonOverlay pattern.
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
                          _BillTile('DTH /\nCable TV', Icons.live_tv_rounded, () {}, locked: true),
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
                      // Single active recharge -- keep the full-width
                      // card, no need to make it feel scrollable when
                      // there's nothing else to scroll to.
                          ? _ActiveRechargeCard(vm.activeRecharges.first)
                      // 2+ active recharges -- horizontally scrollable
                      // strip, soonest-expiring first (backend already
                      // sorts this way). Once one expires it simply
                      // drops out of vm.activeRecharges on the next
                      // load and the rest shift forward -- FIFO, no
                      // client-side expiry bookkeeping needed.
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
            // Auto-toast: "You earned N YouPi Coins! Worth ₹X" -- slides
            // in near the top for a few seconds right after a successful
            // recharge, then slides back out on its own. Sits in a
            // SafeArea of its own (not the one above) so it floats over
            // the header row instead of pushing it down.
            //
            // Reads _toastCoins/_toastValue (mutable state), not
            // widget.earnedCoins/earnedValue directly -- this same toast
            // needs to render for TWO different triggers: the normal
            // sync path (fresh navigation right after a recharge, numbers
            // come from route params) AND the async follow-up path
            // (_checkPendingCoinAnimation, numbers computed later while
            // this same Home instance is already sitting there).
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

  // Real backend data now (via GoldRepository -> HomeViewModel), not the
  // earlier local StorageService stand-in.
  double _goldRewardBalance(HomeViewModel vm) => vm.goldBalanceRupees;

  int _goldCoinCount(HomeViewModel vm) => vm.goldCoinCount;
}

/// Small auto-dismissing banner shown near the top of Home right after a
/// successful recharge -- "You earned N YouPi Coins!" / "Worth ₹X".
/// Purely a transient confirmation; the header coin badge (_GoldRewardCoin
/// below) remains the permanent, always-accurate running total. This shows
/// ONLY the amount from the recharge that was just completed.
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
      // Purely informational -- never blocks taps on the real header/coin
      // badge underneath, even while visible.
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

/// YouPi Coin button shown in the home header (replaces the notification bell).
/// Tapping it opens the Gold Reward popup.
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

/// Gold Reward popup -- shows accumulated YouPi Coins with a Withdraw
/// button. Minimum withdrawal is ₹50. Now calls the REAL /v1/gold/withdraw
/// API via GoldRepository (teammate's work) -- was a 400ms mock before.
class _GoldRewardPopup extends StatefulWidget {
  final double amount;
  final int coinCount;
  const _GoldRewardPopup({required this.amount, required this.coinCount});

  @override
  State<_GoldRewardPopup> createState() => _GoldRewardPopupState();
}

class _GoldRewardPopupState extends State<_GoldRewardPopup> {
  String? _error; // unused this version (withdraw disabled) -- kept for the re-enable below

  // ── WITHDRAW -- DISABLED THIS VERSION, deferred to next version ──
  // Real _withdraw() logic (with the requestId-based idempotency fix) is
  // ready and tested server-side (GoldWithdrawService.kt + V16 migration),
  // just not wired to a live button here. To re-enable next version:
  //   1. Confirm backend V16 migration + GoldWithdrawService.kt (requestId
  //      idempotency fix) are deployed FIRST.
  //   2. Restore this state:
  //        static const double _minWithdraw = 50.0;
  //        bool _busy = false;
  //        late final String _requestId =
  //            'gold_withdraw_${widget.amount}_${DateTime.now().millisecondsSinceEpoch}';
  //        Future<void> _withdraw() async {
  //          if (widget.amount < _minWithdraw) {
  //            setState(() => _error = 'Minimum withdrawal amount is ₹50');
  //            return;
  //          }
  //          setState(() { _error = null; _busy = true; });
  //          try {
  //            final result = await GoldRepository().withdraw(widget.amount, requestId: _requestId);
  //            if (!mounted) return;
  //            context.read<HomeViewModel>().updateGoldWalletAfterWithdraw(result);
  //            setState(() => _busy = false);
  //            Navigator.of(context).pop();
  //            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
  //              content: Text('${CurrencyFormatter.format(result.amountRupees)} credited to wallet'),
  //            ));
  //          } catch (e) {
  //            if (!mounted) return;
  //            setState(() { _busy = false; _error = e.toString().replaceFirst('Exception: ', ''); });
  //          }
  //        }
  //   3. Swap the disabled ElevatedButton below back to:
  //        onPressed: _busy ? null : _withdraw,
  //      and restore its busy-spinner child (see git history / earlier version of this file).

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
              'Earn 1% of every recharge as YouPi Coins',
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
                // Withdraw is deferred to the NEXT version (needs bank
                // payout API, not ready yet) -- button stays fully live/
                // tappable-looking, but tapping shows the same shared
                // "Coming Soon" snack used elsewhere in the app (BNPL,
                // Loan, etc. -- see ComingSoonOverlay.showComingSoonSnack)
                // instead of calling the real /v1/gold/withdraw API.
                // Real _withdraw() logic (with the requestId idempotency
                // fix) is ready server-side whenever bank API lands --
                // see the commented reference block above.
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