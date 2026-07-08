import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_card.dart';
import 'recharge_viewmodel.dart';

class RechargeSuccessScreen extends StatefulWidget {
  const RechargeSuccessScreen({super.key});
  @override
  State<RechargeSuccessScreen> createState() => _RechargeSuccessScreenState();
}

class _RechargeSuccessScreenState extends State<RechargeSuccessScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnim;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _scaleAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn));
    _controller.forward();
  }

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Consumer<RechargeViewModel>(builder: (ctx, vm, _) {
      final plan = vm.selectedPlan;
      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppDimensions.paddingPage),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                ScaleTransition(
                  scale: _scaleAnim,
                  child: Center(
                    child: Container(
                      width: 120, height: 120,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primary, width: 3),
                        boxShadow: [BoxShadow(color: AppColors.primaryGlow, blurRadius: 30, spreadRadius: 8)],
                      ),
                      child: const Icon(Icons.check_rounded, color: AppColors.primary, size: 60),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                FadeTransition(
                  opacity: _fadeAnim,
                  child: Column(
                    children: [
                      Text('Recharge Successful!', style: AppTextStyles.displaySmall, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text('Your recharge has been activated.', style: AppTextStyles.bodyMedium, textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                      if (plan != null) ...[
                        YoupiCard(
                          child: Column(children: [
                            _InfoRow('Mobile', '+91 ${vm.mobile}'),
                            const Divider(color: AppColors.divider, height: 20),
                            _InfoRow('Amount Paid', '₹${vm.selectedEmi?.monthlyAmount.toStringAsFixed(0) ?? plan.price.toStringAsFixed(0)}'),
                            const Divider(color: AppColors.divider, height: 20),
                            _InfoRow('Plan', plan.name),
                            const Divider(color: AppColors.divider, height: 20),
                            _InfoRow('Status', 'SUCCESS', valueColor: AppColors.success),
                          ]),
                        ),
                        if (vm.selectedEmi != null) ...[
                          const SizedBox(height: 12),
                          YoupiCard(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('EMI Schedule',
                                  style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
                              const SizedBox(height: 8),
                              Text('${vm.selectedEmi!.months}x ₹${vm.selectedEmi!.monthlyAmount.toStringAsFixed(0)}/month',
                                  style: AppTextStyles.bodyMedium),
                            ]),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
                const Spacer(),
                YoupiButton(label: 'Go to Home', onPressed: () => ctx.go('/dashboard/home')),
                const SizedBox(height: 10),
                YoupiButton(
                  label: 'Recharge Again',
                  type: YoupiButtonType.secondary,
                  onPressed: () => ctx.go('/dashboard/plans'),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoRow(this.label, this.value, {this.valueColor});
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: AppTextStyles.bodyMedium),
        Text(value, style: AppTextStyles.labelLarge.copyWith(color: valueColor)),
      ],
    );
  }
}
