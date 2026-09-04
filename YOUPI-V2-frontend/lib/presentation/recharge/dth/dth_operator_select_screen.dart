import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/shimmer_loader.dart';
import '../../../core/widgets/youpi_card.dart';
import 'dth_operator_model.dart';
import 'dth_repository.dart';
import 'dth_viewmodel.dart';

class DthOperatorSelectScreen extends StatefulWidget {
  const DthOperatorSelectScreen({super.key});
  @override
  State<DthOperatorSelectScreen> createState() => _DthOperatorSelectScreenState();
}

class _DthOperatorSelectScreenState extends State<DthOperatorSelectScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final vm = context.read<DthViewModel>();
      vm.reset(); // fresh flow every time this screen is entered
      vm.loadOperators();
      vm.loadRecentAccounts();
    });
  }

  // Recents only carry the raw operator `name` (e.g. "AIRTEL DIGITAL TV")
  // -- looks up the matching displayName ("Airtel Digital TV") from
  // whichever operator list is loaded, falling back to the static list,
  // then to the raw name itself if somehow neither has it (an operator
  // that stopped being supported after a past recharge).
  String _displayNameFor(DthViewModel vm, String operatorName) {
    for (final o in vm.operators) {
      if (o.name == operatorName) return o.displayName;
    }
    for (final o in kFallbackDthOperators) {
      if (o.name == operatorName) return o.displayName;
    }
    return operatorName;
  }

  DthOperatorModel _operatorModelFor(DthViewModel vm, String operatorName) {
    for (final o in vm.operators) {
      if (o.name == operatorName) return o;
    }
    for (final o in kFallbackDthOperators) {
      if (o.name == operatorName) return o;
    }
    return DthOperatorModel(name: operatorName, displayName: operatorName);
  }

  // Re-runs the same customer-info lookup DthCustomerIdScreen does before
  // jumping straight to the amount screen -- so a Recents tap still
  // catches an account that's since been closed/changed (the "no account
  // found" case) instead of skipping the check just because it worked
  // last time.
  Future<void> _onTapRecent(DthViewModel vm, DthRecentAccount recent) async {
    vm.selectOperator(_operatorModelFor(vm, recent.operatorName));
    vm.setSubscriberNumber(recent.subscriberNumber);

    final found = await vm.fetchCustomerInfo();
    if (!mounted) return;

    if (found) {
      context.push('/dth/amount');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            vm.customerInfoError ?? 'Could not verify this account. Please enter the subscriber ID again.',
          ),
        ),
      );
      context.push('/dth/customer-id');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DthViewModel>(builder: (ctx, vm, _) {
      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(
          title: Text('DTH Recharge', style: AppTextStyles.headlineMedium),
          backgroundColor: AppColors.backgroundPrimary,
        ),
        body: vm.isLoadingOperators
            ? const ShimmerList()
            : SingleChildScrollView(
                padding: const EdgeInsets.all(AppDimensions.paddingPage),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (vm.recentAccounts.isNotEmpty) ...[
                      Text('Recents', style: AppTextStyles.headlineSmall),
                      const SizedBox(height: 12),
                      ...vm.recentAccounts.map((r) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: YoupiCard(
                              onTap: vm.isFetchingCustomerInfo ? null : () => _onTapRecent(vm, r),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(Icons.tv_rounded, color: AppColors.primary, size: 18),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(_displayNameFor(vm, r.operatorName), style: AppTextStyles.labelLarge),
                                        Text(r.subscriberNumber, style: AppTextStyles.captionText.copyWith(color: AppColors.textSecondary)),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Continue recharge of ₹${r.lastAmount.toStringAsFixed(0)}',
                                          style: AppTextStyles.captionText.copyWith(color: AppColors.primary),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (vm.isFetchingCustomerInfo)
                                    const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  else
                                    Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                                ],
                              ),
                            ),
                          )),
                      const SizedBox(height: 20),
                    ],
                    Text('Select DTH operator', style: AppTextStyles.headlineSmall),
                    const SizedBox(height: 12),
                    ...vm.operators.map((op) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: YoupiCard(
                            onTap: () {
                              vm.selectOperator(op);
                              ctx.push('/dth/customer-id');
                            },
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.tv_rounded, color: AppColors.primary, size: 18),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(op.displayName, style: AppTextStyles.labelLarge),
                                ),
                                Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                              ],
                            ),
                          ),
                        )),
                  ],
                ),
              ),
      );
    });
  }
}