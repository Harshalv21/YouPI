import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';

class SmartDepositScreen extends StatelessWidget {
  const SmartDepositScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(title: const Text('SmartDeposit'), backgroundColor: AppColors.backgroundPrimary),
      body: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.secondary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
                border: Border.all(color: AppColors.secondary.withOpacity(0.4)),
              ),
              child: Column(children: [
                Text('SmartDeposit',
                    style: AppTextStyles.headlineLarge.copyWith(color: AppColors.secondary)),
                Text('Earn 6% interest on unused BNPL limit!', style: AppTextStyles.bodyMedium),
              ]),
            ),
            const SizedBox(height: 24),
            Slider(
              value: 1000,
              min: 100,
              max: 5000,
              activeColor: AppColors.primary,
              inactiveColor: AppColors.divider,
              onChanged: (_) {},
            ),
            Text('Deposit Amount: ₹1,000', style: AppTextStyles.labelLarge),
            const SizedBox(height: 8),
            Text('Expected Monthly Interest: ₹5.00',
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.success)),
            const Spacer(),
            YoupiButton(
              label: 'Enable SmartDeposit',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('SmartDeposit enabled!'), backgroundColor: AppColors.success));
                context.pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
