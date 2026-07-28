import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/coming_soon_overlay.dart';
import '../../core/widgets/shimmer_loader.dart';
import '../../core/widgets/youpi_card.dart';
import 'home_viewmodel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _balanceHidden = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeViewModel>().loadHome();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<HomeViewModel>(builder: (ctx, vm, _) {
      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        body: SafeArea(
          child: vm.isLoading
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
                  // Was previously invisible: if the real profile fetch
                  // failed, the screen silently showed mock data with no
                  // indication anything was wrong. This banner makes that
                  // state visible instead of looking like "the app is just
                  // showing wrong numbers for no reason."
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
                      // TEMPORARY (this version): tapping shows accumulated
                      // recharge reward as YouPi Coins. Augmont gram-conversion
                      // comes in the next version.
                      // TODO(backend): wire `_goldRewardBalance` / `_goldCoinCount`
                      // below to the real accumulated reward total from the API.
                      _GoldRewardCoin(
                        amount: _goldRewardBalance(vm),
                        coinCount: _goldCoinCount(vm),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Balance card -- locked: this card is being repositioned as
                  // "Credit Limit" (NBFC-backed) per director direction, not
                  // ready yet. See conversation notes.
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
                        _QuickAction('Wallet', Icons.account_balance_wallet_rounded, () => ctx.go('/dashboard/wallet')),
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
                      TextButton(
                        onPressed: () => ctx.push('/invest/portfolio'),
                        child: Text('View all',
                            style: AppTextStyles.tealLink.copyWith(decoration: TextDecoration.none)),
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
                  // Active recharge
                  Text('Active Recharge', style: AppTextStyles.headlineSmall),
                  const SizedBox(height: 12),
                  YoupiCard(
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
                        // Lock the "BNPL Boost" offer with a Coming Soon overlay.
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
      );
    });
  }

  // TODO(backend): replace this with the real accumulated gold-reward total.
  // For now returns 0.0 (or a mock value for local UI testing). The reward is
  // 1 YouPi Coin per successful recharge >= ₹249, and that coin's value is
  // 1% of the recharge amount it came from (total value tracked in rupees).
  double _goldRewardBalance(HomeViewModel vm) {
    // return vm.goldRewardBalance; // <-- wire this once backend field exists
    return 0.0;
  }

  // TODO(backend): replace with real count of YouPi Coins earned.
  int _goldCoinCount(HomeViewModel vm) {
    // return vm.goldCoinCount; // <-- wire this once backend field exists
    return 0;
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
        child: Image.asset(
          'assets/images/youpi_coin.png',
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.monetization_on_rounded, color: AppColors.secondary, size: 36),
        ),
      ),
    );
  }
}

/// Gold Reward popup -- shows accumulated YouPi Coins with a Withdraw
/// button. Minimum withdrawal is ₹50 (based on the coins' rupee value);
/// below that an inline error is shown. At/above ₹50 the value is credited
/// to the wallet.
class _GoldRewardPopup extends StatefulWidget {
  final double amount;
  final int coinCount;
  const _GoldRewardPopup({required this.amount, required this.coinCount});

  @override
  State<_GoldRewardPopup> createState() => _GoldRewardPopupState();
}

class _GoldRewardPopupState extends State<_GoldRewardPopup> {
  static const double _minWithdraw = 50.0;
  String? _error;
  bool _busy = false;

  Future<void> _withdraw() async {
    if (widget.amount < _minWithdraw) {
      setState(() => _error = 'Minimum withdrawal amount is ₹50');
      return;
    }

    setState(() {
      _error = null;
      _busy = true;
    });

    // TODO(backend): call withdraw API -> credits `widget.amount` to wallet.
    // await context.read<HomeViewModel>().withdrawGoldReward();
    await Future<void>.delayed(const Duration(milliseconds: 400)); // mock

    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${CurrencyFormatter.format(widget.amount)} credited to wallet'),
      ),
    );
  }

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
              'Earn up to 5% of every recharge as YouPi Coins',
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
                onPressed: _busy ? null : _withdraw,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : Text('Withdraw', style: AppTextStyles.labelLarge.copyWith(color: Colors.black)),
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