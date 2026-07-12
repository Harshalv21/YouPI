import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/currency_formatter.dart';
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
                      Stack(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.notifications_none_rounded,
                                color: AppColors.textPrimary),
                            onPressed: () => context.push('/settings/notifications'),
                          ),
                          Positioned(
                            right: 10,
                            top: 10,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                  color: AppColors.error, shape: BoxShape.circle),
                            ),
                          )
                        ],
                      )
                    ],
                  ),
                  const SizedBox(height: 20),
                  // Balance card
                  YoupiGlassCard(
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
                        _QuickAction('Smart Saver', Icons.savings_rounded, () => ctx.push('/plans/smartsave')),
                        _QuickAction('Wallet', Icons.account_balance_wallet_rounded, () => ctx.go('/dashboard/wallet')),
                        _QuickAction('Gold', Icons.monetization_on_rounded, () => ctx.push('/invest/gold')),
                        _QuickAction('FD Invest', Icons.trending_up_rounded, () => ctx.push('/invest/fd')),
                        _QuickAction('BNPL Shop', Icons.credit_card_rounded, () => ctx.go('/dashboard/bnpl')),
                        _QuickAction('Loan', Icons.account_balance_rounded, () => ctx.push('/loan/apply/step1')),
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
                      _PortfolioMetric('FD Return', '7.5% p.a.', AppColors.primary),
                      const SizedBox(width: 12),
                      _PortfolioMetric('BNPL Limit',
                          CurrencyFormatter.formatNoDecimal(vm.user.bnplLimit - vm.user.bnplUsed), AppColors.primary),
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
                      itemBuilder: (ctx, i) => _OfferCard(vm.offers[i]),
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
}

class _QuickAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _QuickAction(this.label, this.icon, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 72,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.backgroundCard,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.divider),
              ),
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
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
  const _PortfolioMetric(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: YoupiCard(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.labelSmall),
            const SizedBox(height: 4),
            Text(value, style: AppTextStyles.labelLarge.copyWith(color: color), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  final Map<String, String> offer;
  const _OfferCard(this.offer);

  @override
  Widget build(BuildContext context) {
    return Container(
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
  }
}