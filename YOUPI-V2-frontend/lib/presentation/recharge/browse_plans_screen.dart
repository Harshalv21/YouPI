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
  final _searchCtrl = TextEditingController();
  bool _searchExpanded = false;

  // Price chip filtering -- was non-functional (onSelected: (_) {}) before,
  // same broken pattern as the old duplicate Search Plans screen. Bucketed
  // ranges: null = no filter (chip not selected).
  String? _selectedPriceChip;
  static const _priceRanges = <String, (double, double)>{
    '₹100': (0, 100),
    '₹300': (100, 300),
    '₹300–₹500': (300, 500),
    '₹500+': (500, double.infinity),
  };

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RechargeViewModel>().loadPlans();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  List<dynamic> _applyFilters(List<dynamic> plans, String query) {
    var result = plans;
    if (query.isNotEmpty) {
      final q = query.toLowerCase();
      result = result.where((p) =>
      p.name.toLowerCase().contains(q) ||
          p.price.toString().contains(q) ||
          p.dataPerDay.toLowerCase().contains(q) ||
          p.validityDays.toString().contains(q)).toList();
    }
    if (_selectedPriceChip != null) {
      final range = _priceRanges[_selectedPriceChip]!;
      result = result.where((p) => p.price >= range.$1 && p.price < range.$2).toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RechargeViewModel>(builder: (ctx, vm, _) {
      final query = _searchCtrl.text;
      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(
          title: _searchExpanded
              ? TextField(
            controller: _searchCtrl,
            autofocus: true,
            style: AppTextStyles.bodyMedium,
            decoration: InputDecoration(
              hintText: 'Search for a plan, e.g. 349 or 2GB...',
              hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
              border: InputBorder.none,
            ),
            onChanged: (_) => setState(() {}),
          )
              : Text('Browse Plans', style: AppTextStyles.headlineMedium),
          backgroundColor: AppColors.backgroundPrimary,
          actions: [
            IconButton(
              icon: Icon(_searchExpanded ? Icons.close_rounded : Icons.search_rounded),
              onPressed: () => setState(() {
                if (_searchExpanded) _searchCtrl.clear();
                _searchExpanded = !_searchExpanded;
              }),
            ),
          ],
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
            // Price chips -- now actually functional. Tapping toggles the
            // filter on/off (tap the selected chip again to clear it).
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: _priceRanges.keys.map((f) {
                  final selected = _selectedPriceChip == f;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(f, style: AppTextStyles.chipText),
                      selected: selected,
                      onSelected: (isSelected) => setState(() {
                        _selectedPriceChip = isSelected ? f : null;
                      }),
                      backgroundColor: AppColors.backgroundCard,
                      selectedColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.divider),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
                  );
                }).toList(),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _PlansList(plans: _applyFilters(vm.plans, query), vm: vm),
                  // NOTE: "Popular" stays empty for real (non-mock) plans --
                  // the backend never sets isPopular=true (mPlan doesn't
                  // provide this concept, and no ranking logic exists yet
                  // server-side). Not fixed here; needs a backend decision
                  // on what "popular" means before this tab can show anything.
                  _PlansList(
                    plans: _applyFilters(vm.plans.where((p) => p.isPopular).toList(), query),
                    vm: vm,
                  ),
                  _PlansList(
                    plans: _applyFilters(vm.plans.where((p) => p.validityDays >= 84).toList(), query),
                    vm: vm,
                  ),
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
                      // EMI line removed -- EMI is off for this version, so
                      // showing "EMI: 3×₹X" here was stale/misleading even
                      // though the underlying plan.emiOptions data still
                      // exists (unused now, same as the rest of the app).
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