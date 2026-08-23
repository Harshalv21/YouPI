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

  // Validity chip filtering -- filters by plan.validityDays instead of price.
  // null = no filter (chip not selected).
  int? _selectedValidityChip;
  static const _validityOptions = <int>[1, 2, 3, 28, 56, 84];

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
    if (_selectedValidityChip != null) {
      result = result.where((p) => p.validityDays == _selectedValidityChip).toList();
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
            // Validity + data-amount chips, all in one continuous scrollable row.
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  ..._validityOptions.map((days) {
                    final selected = _selectedValidityChip == days;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text('$days ${days == 1 ? 'Day' : 'Days'}', style: AppTextStyles.chipText),
                        selected: selected,
                        onSelected: (isSelected) => setState(() {
                          _selectedValidityChip = isSelected ? days : null;
                        }),
                        backgroundColor: AppColors.backgroundCard,
                        selectedColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.divider),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    );
                  }),
                ],
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
            padding: EdgeInsets.zero, // hum andar khud padding control karenge (badge full-width chahiye)
            onTap: () {
              vm.selectPlan(plan);
              ctx.push('/plans/emi-select');
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ---- Top badge strip (category/tier) ----
                if (plan.tier.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.15),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        topRight: Radius.circular(12),
                      ),
                    ),
                    child: Text(
                      plan.tier,
                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ---- Price + Plan name row ----
                      // ← Chevron-circle button hataya -- poora card already
                      // tappable hai (YoupiCard.onTap upar), so a second
                      // "go" affordance next to the name was redundant.
                      // Name now gets the full remaining width instead of
                      // being squeezed by that button.
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('₹${plan.price.toStringAsFixed(0)}',
                              style: AppTextStyles.headlineSmall),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              plan.name,
                              style: AppTextStyles.labelLarge,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Divider(color: AppColors.divider, height: 1),
                      const SizedBox(height: 12),

                      // ---- 2-column grid: Validity | Data / Calls | Extras ----
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _InfoColumn(label: 'Validity', value: '${plan.validityDays} Days'),
                          ),
                          Expanded(
                            child: _InfoColumn(label: 'Data', value: plan.dataPerDay),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _InfoColumn(label: 'Calls', value: plan.callsInfo),
                          ),
                          Expanded(
                            child: _InfoColumn(
                              label: 'SMS/Extras',
                              value: plan.extras.isNotEmpty ? plan.extras.join(', ') : '—',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InfoColumn extends StatelessWidget {
  final String label;
  final String value;
  const _InfoColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        Text(value, style: AppTextStyles.labelMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}