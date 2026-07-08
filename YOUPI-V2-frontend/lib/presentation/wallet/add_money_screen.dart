import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';

class AddMoneyScreen extends StatelessWidget {
  const AddMoneyScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(title: const Text('Add Money'), backgroundColor: AppColors.backgroundPrimary),
      body: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Enter Amount', style: AppTextStyles.displaySmall),
            const SizedBox(height: 24),
            TextField(
              keyboardType: TextInputType.number,
              style: AppTextStyles.amountLarge,
              textAlign: TextAlign.center,
              decoration: InputDecoration(
                prefixText: '₹ ',
                hintText: '0',
                border: InputBorder.none,
                prefixStyle: AppTextStyles.amountLarge,
                hintStyle: AppTextStyles.amountLarge.copyWith(color: AppColors.textSecondary),
              ),
            ),
            const Divider(color: AppColors.primary, thickness: 2),
            const SizedBox(height: 20),
            Wrap(spacing: 8, children: ['₹500', '₹1,000', '₹2,000', '₹5,000']
                .map((a) => OutlinedButton(
                      onPressed: () {},
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary)),
                      child: Text(a),
                    )).toList()),
            const Spacer(),
            YoupiButton(
              label: 'Add Money',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Money added!'), backgroundColor: AppColors.success));
                context.pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
