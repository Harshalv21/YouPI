import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/widgets/shimmer_loader.dart';
import '../../../core/widgets/youpi_card.dart';
import 'dth_operator_model.dart';
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
    });
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