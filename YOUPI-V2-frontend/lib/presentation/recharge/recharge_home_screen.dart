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
import 'recharge_contact_picker_screen.dart';
import 'recharge_history_screen.dart';
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
      final vm = context.read<RechargeViewModel>();
      vm.loadPlans();
      vm.loadRecentRecharges(); // NEW: fetch last few recharges for this number
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
              onPressed: () => ctx.push('/plans/browse'),
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
              Row(
                children: [
                  Expanded(
                    child: YoupiCard(
                      onTap: () => _showEditMobileDialog(context, vm),
                      child: Row(
                        children: [
                          const Icon(Icons.phone_android_rounded, color: AppColors.primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: vm.mobile.isEmpty
                                ? Text(
                              '00000 00000',
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
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.contacts_rounded, color: AppColors.textSecondary, size: 22),
                    onPressed: () => _openContactPicker(context, vm),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  _OperatorSlotChip(vm: vm),
                ],
              ),
              const SizedBox(height: 20),

              // ---------------- Recent Recharges strip (NEW) ----------------
              if (vm.isLoadingRecent)
                const Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: SizedBox(
                    height: 84,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                )
              else if (vm.recentRecharges.isNotEmpty) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Recent Recharges', style: AppTextStyles.headlineSmall),
                    TextButton(
                      onPressed: () async {
                        await vm.loadAllRechargeHistory();
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).push(
                          MaterialPageRoute(
                            builder: (_) => RechargeHistoryScreen(
                              allRecords: vm.allRechargeHistory,
                            ),
                          ),
                        );
                      },
                      child: Text(
                        'View All',
                        style: AppTextStyles.tealLink.copyWith(decoration: TextDecoration.none),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: vm.recentRecharges.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final r = vm.recentRecharges[index];
                      return GestureDetector(
                        onTap: () {
                          vm.repeatRecharge(r);
                          ctx.push('/plans/emi-select');
                        },
                        child: Container(
                          width: 170,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundCard,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.textSecondary.withOpacity(0.1)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(r.operator, style: AppTextStyles.labelLarge),
                                  const Spacer(),
                                  Text(
                                    '₹${r.amount.toStringAsFixed(0)}',
                                    style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary),
                                  ),
                                ],
                              ),
                              Text(
                                r.mobileNumber,
                                style: AppTextStyles.captionText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${r.createdAt.day}/${r.createdAt.month}',
                                    style: AppTextStyles.captionText,
                                  ),
                                  const Icon(Icons.refresh, size: 14, color: AppColors.primary),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),
              ],
              // -------------- end Recent Recharges strip (NEW) --------------

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

Future<void> _openContactPicker(BuildContext context, RechargeViewModel vm) async {
  final selected = await Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const RechargeContactPickerScreen()),
  );
  if (selected != null && selected.length == 10) {
    vm.setMobile(selected);
    vm.loadRecentRecharges(); // NEW: refresh recent recharges when number changes via contact picker
  }
}

void _showEditMobileDialog(BuildContext context, RechargeViewModel vm) {
  final ctrl = TextEditingController(text: vm.mobile);
  bool showInvalid = false;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        backgroundColor: AppColors.backgroundCard,
        title: Text('Enter mobile number', style: AppTextStyles.headlineSmall),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
  decoration: BoxDecoration(
    border: Border.all(color: AppColors.primary, width: 1.5),
    borderRadius: BorderRadius.circular(10),
  ),
  child: Row(
    children: [
      Text('+91', style: AppTextStyles.bodyMedium),
      const SizedBox(width: 8),
      Container(
        width: 1,
        height: 20,
        color: AppColors.textSecondary.withOpacity(0.3),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.phone,
          maxLength: 10,
          enableInteractiveSelection: false,
          showCursor: true,
          style: AppTextStyles.bodyMedium,
          decoration: const InputDecoration(
            hintText: '00000 00000',
            counterText: '',
            border: InputBorder.none,
            focusedBorder: InputBorder.none,
            enabledBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            isDense: true,
          ),
          onChanged: (val) {
            setDialogState(() {
              showInvalid = val.isNotEmpty && val.length != 10;
            });
          },
        ),
      ),
    ],
  ),
),
            if (showInvalid)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Text(
                  'Ensure this is a valid mobile number',
                  style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
                ),
              ),
          ],
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
                vm.loadRecentRecharges(); // NEW: refresh recent recharges when number changes manually
                Navigator.of(ctx).pop();
              } else {
                setDialogState(() => showInvalid = true);
              }
            },
            child: Text('Confirm', style: AppTextStyles.tealLink),
          ),
        ],
      ),
    ),
  );
}

class _OperatorSlotChip extends StatelessWidget {
  final RechargeViewModel vm;
  const _OperatorSlotChip({required this.vm});

  @override
  Widget build(BuildContext context) {
    final state = vm.detectionState;

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