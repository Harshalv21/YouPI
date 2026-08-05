import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_input.dart';

class BnplApplyStep2Screen extends StatelessWidget {
  const BnplApplyStep2Screen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(backgroundColor: AppColors.backgroundPrimary, title: const Text('Apply for BNPL')),
      // BUG FIX: same Column+Spacer overflow issue as mpin_entry_screen.dart
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppDimensions.paddingPage),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - (AppDimensions.paddingPage * 2),
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    LinearProgressIndicator(value: 2 / 3,
                        backgroundColor: AppColors.divider, valueColor: const AlwaysStoppedAnimation(AppColors.primary)),
                    const SizedBox(height: 8),
                    Text('Step 2 of 3 • Personal Details', style: AppTextStyles.labelMedium),
                    const SizedBox(height: 24),
                    YoupiInput(label: 'City', hint: 'e.g. Lucknow'),
                    const SizedBox(height: 16),
                    YoupiInput(label: 'State', hint: 'e.g. Uttar Pradesh'),
                    const SizedBox(height: 16),
                    YoupiInput(label: 'Bank Account (Optional)', hint: 'XXXXXXXXXXXXXXXX'),
                    const Spacer(),
                    YoupiButton(
                      label: 'Next',
                      onPressed: () => context.push('/bnpl/apply/step3'),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}