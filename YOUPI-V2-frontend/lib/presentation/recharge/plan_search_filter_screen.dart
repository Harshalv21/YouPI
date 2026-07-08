import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_card.dart';
import 'recharge_viewmodel.dart';

class PlanSearchFilterScreen extends StatelessWidget {
  const PlanSearchFilterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<RechargeViewModel>(builder: (ctx, vm, _) {
      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(backgroundColor: AppColors.backgroundPrimary,
            title: Text('Search Plans', style: AppTextStyles.headlineMedium)),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppDimensions.paddingPage),
              child: TextField(
                onChanged: vm.setSearchQuery,
                autofocus: true,
                style: AppTextStyles.inputValue,
                decoration: InputDecoration(
                  hintText: 'Search for a plan, e.g. 349 or 2GB...',
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
                  filled: true,
                  fillColor: AppColors.backgroundCard,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusInput),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusInput),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusInput),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                ),
              ),
            ),
            // Filter chips
            SizedBox(
              height: 48,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: ['Unlimited', '5G', '2GB/Day', '1.5GB/Day', 'Long Term', 'Popular', 'Data', 'International']
                    .map((f) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(f, style: AppTextStyles.chipText),
                            selected: false,
                            onSelected: (_) {},
                            backgroundColor: AppColors.backgroundCard,
                            side: const BorderSide(color: AppColors.divider),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
            // SmartSave banner
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.secondary.withOpacity(0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('✨ NEW — SmartSave Advantage',
                        style: AppTextStyles.labelLarge.copyWith(color: AppColors.secondary)),
                    Text('Same benefits • Pay in 3 easy instalments • Save ₹147',
                        style: AppTextStyles.bodySmall),
                    Text('Same benefits at ₹300/month', style: AppTextStyles.captionText.copyWith(color: AppColors.secondary)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: vm.filteredPlans.isEmpty
                  ? Center(child: Text('No plans found', style: AppTextStyles.bodyMedium))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: vm.filteredPlans.length,
                      itemBuilder: (ctx, i) {
                        final plan = vm.filteredPlans[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: YoupiCard(
                            onTap: () {
                              vm.selectPlan(plan);
                              ctx.push('/plans/emi-select');
                            },
                            child: Row(children: [
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('₹${plan.price.toStringAsFixed(0)}', style: AppTextStyles.headlineSmall),
                                  Text('${plan.validityDays} days • ${plan.dataPerDay}/day • ${plan.callsInfo}',
                                      style: AppTextStyles.bodySmall),
                                  if (plan.hasEmi)
                                    Text('SmartSave ₹${plan.emiOptions.first.monthlyAmount.toStringAsFixed(0)}/mo',
                                        style: AppTextStyles.captionText.copyWith(color: AppColors.primary)),
                                ]),
                              ),
                              if (plan.isPopular)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text('Popular',
                                      style: AppTextStyles.labelSmall.copyWith(color: AppColors.backgroundPrimary)),
                                ),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    });
  }
}
