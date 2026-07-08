import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';

class SendMoneyScreen extends StatelessWidget {
  const SendMoneyScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(title: const Text('Send Money'), backgroundColor: AppColors.backgroundPrimary),
      body: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Send via UPI / Mobile', style: AppTextStyles.displaySmall),
            const SizedBox(height: 24),
            TextField(
              keyboardType: TextInputType.phone,
              style: AppTextStyles.inputValue,
              decoration: InputDecoration(
                hintText: 'Mobile / UPI ID',
                filled: true,
                fillColor: AppColors.backgroundCard,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusInput),
                    borderSide: const BorderSide(color: AppColors.divider)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusInput),
                    borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppDimensions.radiusInput),
                    borderSide: const BorderSide(color: AppColors.divider)),
              ),
            ),
            const SizedBox(height: 16),
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
              label: 'Send',
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Money sent!'), backgroundColor: AppColors.success));
                context.pop();
              },
            ),
          ],
        ),
      ),
    );
  }
}
