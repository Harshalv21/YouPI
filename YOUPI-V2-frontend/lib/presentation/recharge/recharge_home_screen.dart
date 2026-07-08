import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/shimmer_loader.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_card.dart';
import 'recharge_viewmodel.dart';

class RechargeHomeScreen extends StatefulWidget {
  const RechargeHomeScreen({super.key});
  @override
  State<RechargeHomeScreen> createState() => _RechargeHomeScreenState();
}

class _RechargeHomeScreenState extends State<RechargeHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RechargeViewModel>().loadPlans();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RechargeViewModel>(builder: (ctx, vm, _) {
      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(
          title: Text('Mobile Recharge', style: AppTextStyles.headlineMedium),
          backgroundColor: AppColors.backgroundPrimary,
          actions: [
            IconButton(
              icon: const Icon(Icons.search_rounded),
              onPressed: () => ctx.push('/plans/search'),
            )
          ],
        ),
        body: vm.isLoading
            ? const ShimmerList()
            : SingleChildScrollView(
                padding: const EdgeInsets.all(AppDimensions.paddingPage),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Mobile row
                    YoupiCard(
                      child: Row(
                        children: [
                          const Icon(Icons.phone_android_rounded, color: AppColors.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text('+91 ${vm.mobile}', style: AppTextStyles.headlineSmall),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_rounded, color: AppColors.textSecondary, size: 18),
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Operator chips
                    Wrap(
                      spacing: 8,
                      children: [
                        Chip(
                          label: Text('${vm.operator.toUpperCase()} • ${vm.circle}',
                              style: AppTextStyles.chipText.copyWith(color: AppColors.primary)),
                          backgroundColor: AppColors.primary.withOpacity(0.1),
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // EMI banner
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.backgroundCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Pay via EMI', style: AppTextStyles.labelLarge),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _EmiChip('3 EMI × ₹116', true),
                              const SizedBox(width: 8),
                              _EmiChip('6 EMI × ₹60', false),
                            ],
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Best Selling Plans', style: AppTextStyles.headlineSmall),
                        TextButton(
                          onPressed: () => ctx.push('/plans/browse'),
                          child: Text('Browse All', style: AppTextStyles.tealLink.copyWith(decoration: TextDecoration.none)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...vm.plans.take(3).map((plan) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: YoupiCard(
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
                                  Row(children: [
                                    Text(plan.name, style: AppTextStyles.labelLarge),
                                    if (plan.isPopular) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text('Popular',
                                            style: AppTextStyles.labelSmall.copyWith(
                                                color: AppColors.backgroundPrimary)),
                                      ),
                                    ]
                                  ]),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${plan.dataPerDay}/day • ${plan.validityDays} Days • ${plan.callsInfo}',
                                    style: AppTextStyles.bodySmall,
                                  ),
                                  if (plan.extras.isNotEmpty)
                                    Text(plan.extras.first, style: AppTextStyles.captionText.copyWith(color: AppColors.secondary)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('₹${plan.price.toStringAsFixed(0)}',
                                    style: AppTextStyles.headlineSmall.copyWith(color: AppColors.primary)),
                                if (plan.hasEmi)
                                  Text('EMI from ₹${plan.emiOptions.first.monthlyAmount.toStringAsFixed(0)}/mo',
                                      style: AppTextStyles.captionText),
                              ],
                            ),
                          ],
                        ),
                      ),
                    )).toList(),
                    // Bottom offer banner
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppColors.primary.withOpacity(0.15), AppColors.backgroundCard],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.local_offer_rounded, color: AppColors.primary),
                        const SizedBox(width: 10),
                        Expanded(child: Text('Special Offer — Get 10% Cashback on EMI Recharges',
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textPrimary))),
                      ]),
                    ),
                  ],
                ),
              ),
      );
    });
  }
}

class _EmiChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  const _EmiChip(this.label, this.isSelected);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary : AppColors.backgroundSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isSelected ? AppColors.primary : AppColors.divider),
      ),
      child: Text(
        label,
        style: AppTextStyles.chipText.copyWith(
          color: isSelected ? AppColors.backgroundPrimary : AppColors.textPrimary,
        ),
      ),
    );
  }
}
