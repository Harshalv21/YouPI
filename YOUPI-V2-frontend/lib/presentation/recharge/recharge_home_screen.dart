import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/shimmer_loader.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_card.dart';
import '../../core/widgets/contact_picker_field.dart';
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
              // Was '/plans/search' -- that screen's filter chips were
              // non-functional and duplicated this Browse Plans screen.
              // Consolidated to one working plans screen.
              onPressed: () => ctx.push('/plans/browse'),
            )
          ],
        ),
        // isPlansRefreshing (silent reload after operator detection) does
        // NOT trigger this -- only the genuine first-time load does. That
        // keeps the screen (mobile number, operator chip, scroll position)
        // stable instead of flashing back to a full shimmer reload.
        body: vm.isLoading
            ? const ShimmerList()
            : SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.paddingPage),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Mobile row
              YoupiCard(
                onTap: vm.mobile.isEmpty ? () => _showEditMobileDialog(context, vm) : null,
                child: Row(
                  children: [
                    const Icon(Icons.phone_android_rounded, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: vm.mobile.isEmpty
                          ? Text(
                        'Enter mobile number',
                        style: AppTextStyles.headlineSmall.copyWith(
                          color: AppColors.textSecondary.withOpacity(0.6),
                        ),
                      )
                          : Text('+91 ${vm.mobile}', style: AppTextStyles.headlineSmall),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_rounded, color: AppColors.textSecondary, size: 18),
                      onPressed: () => _showEditMobileDialog(context, vm),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Operator detection chip -- blank before a full number is
              // entered, shows a plain "Detecting..." state while mPlan's
              // HLR call is in flight, then settles on the real detected
              // operator/circle. (Decoy-name slot-machine spin removed.)
              Wrap(
                spacing: 8,
                children: [
                  _OperatorSlotChip(vm: vm),
                ],
              ),
              const SizedBox(height: 20),
              // EMI banner + cashback banner removed -- full-amount-only for
              // this version, per launch scope. No payment-mode picker
              // offered anywhere in the recharge flow now (see
              // emi_selection_screen.dart, which always confirms FULL).
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
                  padding: EdgeInsets.zero,
                  onTap: () {
                    vm.selectPlan(plan);
                    ctx.push('/plans/emi-select');
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  plan.tier,
                                  style: AppTextStyles.labelSmall.copyWith(color: AppColors.primary),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (plan.isPopular)
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
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(plan.name,
                                      style: AppTextStyles.labelLarge,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${plan.dataPerDay}/day • ${plan.validityDays} Days • ${plan.callsInfo}',
                                    style: AppTextStyles.bodySmall,
                                  ),
                                  if (plan.extras.isNotEmpty)
                                    Text(plan.extras.first,
                                        style: AppTextStyles.captionText.copyWith(color: AppColors.secondary)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('₹${plan.price.toStringAsFixed(0)}',
                                    style: AppTextStyles.headlineSmall.copyWith(color: AppColors.primary)),
                                const SizedBox(height: 6),
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: const BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.chevron_right_rounded,
                                    size: 20,
                                    color: AppColors.backgroundPrimary,
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
              )).toList(),
            ],
          ),
        ),
      );
    });
  }
}

void _showEditMobileDialog(BuildContext context, RechargeViewModel vm) {
  final ctrl = TextEditingController(text: vm.mobile);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.backgroundCard,
      title: Text('Recharge For', style: AppTextStyles.headlineSmall),
      content: SizedBox(
        width: double.maxFinite,
        child: ContactPickerField(
          controller: ctrl,
          // Selecting a contact fills the number but doesn't auto-submit --
          // user still taps Confirm, same as manual entry, so they get a
          // chance to double check before plans load.
          onNumberSelected: (number, name) {},
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('Cancel', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: () {
            final val = ctrl.text.trim();
            if (val.length == 10) {
              vm.setMobile(val);
              // NOTE: no explicit loadPlans() here anymore -- setMobile()
              // now triggers operator detection, which calls loadPlans()
              // itself once the real operator/circle is known (or
              // detection fails and falls back). Calling it immediately
              // here would fetch plans for the stale/default operator
              // before detection even finishes.
              Navigator.of(ctx).pop();
            }
          },
          child: Text('Confirm', style: AppTextStyles.tealLink),
        ),
      ],
    ),
  );
}

/// Operator/circle detection chip.
///   idle       -- blank ("— • —"), shown before a full 10-digit number
///   detecting  -- shows a simple "Detecting..." state with a small
///                 spinner while the real mPlan HLR call is in flight
///                 (no decoy operator-name cycling anymore)
///   success    -- settles on the real detected "JIO • UP EAST" etc.
///   failed     -- falls back to whatever operator/circle was already
///                 set, so the flow stays usable rather than blocking
class _OperatorSlotChip extends StatelessWidget {
  final RechargeViewModel vm;
  const _OperatorSlotChip({required this.vm});

  @override
  Widget build(BuildContext context) {
    final state = vm.detectionState;

    // Nothing shown while idle or detecting -- no placeholder text, no
    // spinner, no chip at all. Matches apps like GPay where the UI stays
    // silent during the fetch and the result just appears once it's ready.
    if (state == OperatorDetectionState.idle ||
        state == OperatorDetectionState.detecting) {
      return const SizedBox.shrink();
    }

    String displayText;
    Color color;
    IconData? icon;

    switch (state) {
      case OperatorDetectionState.success:
        displayText = '${vm.operator.toUpperCase()} • ${vm.circle}';
        color = AppColors.primary;
        icon = Icons.check_circle_rounded;
        break;
      case OperatorDetectionState.failed:
        displayText = '${vm.operator.toUpperCase()} • ${vm.circle}';
        color = AppColors.error;
        icon = Icons.warning_amber_rounded;
        break;
      default:
        return const SizedBox.shrink();
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: ClipRect(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, animation) => ClipRect(
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
                  .animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
              child: FadeTransition(opacity: animation, child: child),
            ),
          ),
          child: Row(
            key: ValueKey('$state-$displayText'),
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
              ],
              Text(
                displayText,
                style: AppTextStyles.chipText.copyWith(color: color, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }
}