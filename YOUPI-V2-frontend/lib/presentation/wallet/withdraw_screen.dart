import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';

class WithdrawScreen extends StatelessWidget {
  const WithdrawScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(title: const Text('Withdraw'), backgroundColor: AppColors.backgroundPrimary),
      body: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Withdraw Funds', style: AppTextStyles.displaySmall),
            const SizedBox(height: 8),
            Text('Transfers to your bank account within 24 hours.',
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 24),
            TextField(
              keyboardType: TextInputType.number,
              style: AppTextStyles.amountMedium,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                prefixText: '₹ ',
                hintText: '0',
                border: InputBorder.none,
                hintStyle: AppTextStyles.amountMedium.copyWith(color: AppColors.textSecondary),
              ),
            ),
            const Divider(color: AppColors.primary, thickness: 2),
            const Spacer(),
            YoupiButton(
              label: 'Withdraw',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Withdrawal initiated!'), backgroundColor: AppColors.primary));
                context.pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
