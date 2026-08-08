import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/contact_picker_field.dart';
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
  // GPay-style inline number entry -- replaces the old edit-dialog.
  // Kept in sync with vm.mobile both ways: typing here calls vm.setMobile,
  // and picking a number via the full contact-picker screen (_openContactPicker)
  // pushes the result back into this controller.
  final _mobileCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm = context.read<RechargeViewModel>();
      // Deliberately NOT prefilling from vm.mobile -- the viewmodel is a
      // long-lived Provider, so its old value would otherwise "leak" back
      // in every time this screen re-opens. GPay always starts empty, so
      // we reset both the field and the viewmodel's state to match.
      _mobileCtrl.clear();
      vm.setMobile('');
      vm.loadPlans();
      vm.loadRecentRecharges();
    });
    // Handles the plain "typed the number manually, no suggestion tapped"
    // case -- ContactPickerField's onNumberSelected only fires on a tap.
    _mobileCtrl.addListener(() {
      final vm = context.read<RechargeViewModel>();
      final typed = _mobileCtrl.text.trim();
      if (typed.length == 10 && typed != vm.mobile) {
        vm.setMobile(typed);
        vm.loadRecentRecharges();
      }
    });
  }

  @override
  void dispose() {
    _mobileCtrl.dispose();
    super.dispose();
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
              // Mobile row -- GPay-style inline entry with live contact
              // suggestions (ContactPickerField) + a contacts icon that
              // opens the full native-style picker for browsing.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ContactPickerField(
                      controller: _mobileCtrl,
                      onNumberSelected: (number, name) {
                        vm.setMobile(number);
                        vm.loadRecentRecharges();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.contacts_rounded, color: AppColors.textSecondary, size: 22),
                    onPressed: () => _openContactPicker(context, vm, _mobileCtrl),
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
                        onTap: () => showModalBottomSheet(
                          context: ctx,
                          backgroundColor: Colors.transparent,
                          isScrollControlled: true,
                          builder: (_) => RechargeDetailSheet(record: r),
                        ),
                        child: Container(
                          width: 170,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.backgroundCard,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: AppColors.textSecondary.withOpacity(0.1)),
                          ),
                          child: Stack(
                            children: [
                            Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              ContactAvatar(mobileNumber: r.mobileNumber, radius: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: FutureBuilder<Contact?>(
                                  future: ContactLookup.matchNumber(r.mobileNumber),
                                  builder: (context, snapshot) {
                                    final name = snapshot.data?.displayName;
                                    final hasName = name != null && name.trim().isNotEmpty;
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          hasName ? name : r.mobileNumber,
                                          style: AppTextStyles.labelSmall,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (hasName)
                                          Text(
                                            r.mobileNumber,
                                            style: AppTextStyles.captionText.copyWith(color: AppColors.textSecondary),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '₹${r.amount.toStringAsFixed(0)}',
                                          style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ],
                            ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => vm.hideRecentRecharge(r.id),
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppColors.backgroundPrimary,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: AppColors.textSecondary.withOpacity(0.2)),
                                    ),
                                    child: Icon(Icons.close, size: 12, color: AppColors.textSecondary),
                                  ),
                                ),
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

Future<void> _openContactPicker(
    BuildContext context, RechargeViewModel vm, TextEditingController mobileCtrl) async {
  final selected = await Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => const RechargeContactPickerScreen()),
  );
  if (selected != null && selected.length == 10) {
    mobileCtrl.text = selected; // keep the inline field in sync
    vm.setMobile(selected);
    vm.loadRecentRecharges(); // NEW: refresh recent recharges when number changes via contact picker
  }
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