import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_card.dart';
import 'recharge_viewmodel.dart';

class BrowsePlansScreen extends StatefulWidget {
  const BrowsePlansScreen({super.key});
  @override
  State<BrowsePlansScreen> createState() => _BrowsePlansScreenState();
}

class _BrowsePlansScreenState extends State<BrowsePlansScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RechargeViewModel>().loadPlans();
    });
  }
  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Consumer<RechargeViewModel>(builder: (ctx, vm, _) {
      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(
          title: Text('Browse Plans', style: AppTextStyles.headlineMedium),
          backgroundColor: AppColors.backgroundPrimary,
          bottom: TabBar(
            controller: _tabCtrl,
            tabs: const [Tab(text: 'All'), Tab(text: 'Popular'), Tab(text: 'Annual')],
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
          ),
        ),
        body: Column(
          children: [
            // Price chips
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: ['₹100', '₹300', '₹300–₹500', '₹500+'].map((f) =>
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(f, style: AppTextStyles.chipText),
                      selected: false,
                      onSelected: (_) {},
                      backgroundColor: AppColors.backgroundCard,
                      selectedColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.divider),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  )
                ).toList(),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _PlansList(plans: vm.plans, vm: vm),
                  _PlansList(plans: vm.plans.where((p) => p.isPopular).toList(), vm: vm),
                  _PlansList(plans: vm.plans.where((p) => p.validityDays >= 84).toList(), vm: vm),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.backgroundSurface,
            border: const Border(top: BorderSide(color: AppColors.divider)),
          ),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.secondary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.secondary.withOpacity(0.4)),
            ),
            child: Text(
              'Yearly Obsidian Elite — Get 20% cashback on all recharges — ₹499',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondary),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    });
  }
}

class _PlansList extends StatelessWidget {
  final List plans;
  final RechargeViewModel vm;
  const _PlansList({required this.plans, required this.vm});

  @override
  Widget build(BuildContext context) {
    if (plans.isEmpty) {
      return Center(child: Text('No plans found', style: AppTextStyles.bodyMedium));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: plans.length,
      itemBuilder: (ctx, i) {
        final plan = plans[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: YoupiCard(
            showGlow: plan.isPopular,
            onTap: () {
              vm.selectPlan(plan);
              ctx.push('/plans/emi-select');
            },
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (plan.tier.isNotEmpty)
                        Text(plan.tier,
                            style: AppTextStyles.labelSmall.copyWith(color: AppColors.secondary)),
                      Text(plan.name, style: AppTextStyles.labelLarge),
                      Text('${plan.dataPerDay}/day • ${plan.validityDays} days • ${plan.callsInfo}',
                          style: AppTextStyles.bodySmall),
                      if (plan.emiOptions.isNotEmpty)
                        Text('EMI: ${plan.emiOptions.first.months}×₹${plan.emiOptions.first.monthlyAmount.toStringAsFixed(0)}',
                            style: AppTextStyles.captionText.copyWith(color: AppColors.primary)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('₹${plan.price.toStringAsFixed(0)}',
                          style: AppTextStyles.labelLarge.copyWith(color: AppColors.backgroundPrimary)),
                    ),
                  ],
                )
              ],
            ),
          ),
        );
      },
    );
  }
}
