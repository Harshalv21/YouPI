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
              // Operator detection -- casino slot-machine reveal. Blank
              // before a full number is entered, spins through decoy
              // operator names while mPlan's HLR call is in flight, then
              // settles on the real detected operator/circle.
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
                              Flexible(child: Text(plan.name, style: AppTextStyles.labelLarge)),
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
                        ],
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

/// Casino slot-machine style operator/circle detection chip.
///   idle       -- blank ("— • —"), shown before a full 10-digit number
///   detecting  -- rapidly cycles through decoy operator names (spin
///                 effect) while the real mPlan HLR call is in flight
///   success    -- settles on the real detected "JIO • UP EAST" etc.
///   failed     -- falls back to whatever operator/circle was already
///                 set, so the flow stays usable rather than blocking
class _OperatorSlotChip extends StatefulWidget {
  final RechargeViewModel vm;
  const _OperatorSlotChip({required this.vm});

  @override
  State<_OperatorSlotChip> createState() => _OperatorSlotChipState();
}

class _OperatorSlotChipState extends State<_OperatorSlotChip> {
  static const _decoyOperators = ['AIRTEL', 'JIO', 'VI', 'BSNL', 'MTNL'];
  Timer? _spinTimer;
  int _spinIndex = 0;

  @override
  void initState() {
    super.initState();
    _syncSpinState();
  }

  @override
  void didUpdateWidget(covariant _OperatorSlotChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // NOTE: widget.vm is the SAME mutable ChangeNotifier instance every
    // rebuild (Provider doesn't replace it), so comparing oldWidget.vm's
    // field to widget.vm's field here would always show equal -- both
    // point at the identical object. Reading the CURRENT state directly
    // and keeping our own "am I already spinning" flag (via _spinTimer)
    // is what actually makes start/stop idempotent and correct.
    _syncSpinState();
  }

  void _syncSpinState() {
    final state = widget.vm.detectionState;
    final isSpinning = _spinTimer != null;
    if (state == OperatorDetectionState.detecting && !isSpinning) {
      _spinTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
        if (!mounted) return;
        setState(() => _spinIndex = (_spinIndex + 1) % _decoyOperators.length);
      });
    } else if (state != OperatorDetectionState.detecting && isSpinning) {
      _spinTimer?.cancel();
      _spinTimer = null;
    }
  }

  @override
  void dispose() {
    _spinTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.vm.detectionState;

    String displayText;
    Color color;
    IconData? icon;

    switch (state) {
      case OperatorDetectionState.idle:
        displayText = '— • —';
        color = AppColors.textSecondary;
        icon = null;
        break;
      case OperatorDetectionState.detecting:
        displayText = _decoyOperators[_spinIndex];
        color = AppColors.secondary;
        icon = Icons.casino_rounded;
        break;
      case OperatorDetectionState.success:
        displayText = '${widget.vm.operator.toUpperCase()} • ${widget.vm.circle}';
        color = AppColors.primary;
        icon = Icons.check_circle_rounded;
        break;
      case OperatorDetectionState.failed:
        displayText = '${widget.vm.operator.toUpperCase()} • ${widget.vm.circle}';
        color = AppColors.error;
        icon = Icons.warning_amber_rounded;
        break;
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
          // Fast swaps while spinning (matches the timer interval so the
          // slide-in never looks laggy behind the text change); a
          // noticeably slower, more deliberate transition for the final
          // settle -- that's the "jackpot landing" beat.
          duration: Duration(
            milliseconds: state == OperatorDetectionState.detecting ? 90 : 400,
          ),
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