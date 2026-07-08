// BNPL Apply — Step 1: Employment
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_input.dart';

class BnplApplyStep1Screen extends StatefulWidget {
  const BnplApplyStep1Screen({super.key});
  @override State<BnplApplyStep1Screen> createState() => _BnplApplyStep1ScreenState();
}

class _BnplApplyStep1ScreenState extends State<BnplApplyStep1Screen> {
  String _employment = 'Salaried';
  final _incomeCtrl = TextEditingController();
  @override
  void dispose() { _incomeCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(backgroundColor: AppColors.backgroundPrimary, title: const Text('Apply for BNPL')),
      body: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: 1 / 3,
                backgroundColor: AppColors.divider, valueColor: const AlwaysStoppedAnimation(AppColors.primary)),
            const SizedBox(height: 8),
            Text('Step 1 of 3 • Employment Details', style: AppTextStyles.labelMedium),
            const SizedBox(height: 24),
            Text('Employment Type', style: AppTextStyles.inputLabel),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: ['Salaried', 'Self-employed', 'Business Owner', 'Student', 'Homemaker', 'Retired']
                  .map((e) => GestureDetector(
                    onTap: () => setState(() => _employment = e),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: _employment == e ? AppColors.primary.withOpacity(0.1) : AppColors.backgroundCard,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _employment == e ? AppColors.primary : AppColors.divider),
                      ),
                      child: Text(e,
                          style: AppTextStyles.chipText.copyWith(
                            color: _employment == e ? AppColors.primary : AppColors.textPrimary)),
                    ),
                  )).toList(),
            ),
            const SizedBox(height: 20),
            YoupiInput(
              label: 'Monthly Income',
              hint: '₹25,000',
              controller: _incomeCtrl,
              keyboardType: TextInputType.number,
            ),
            const Spacer(),
            YoupiButton(
              label: 'Next',
              onPressed: _incomeCtrl.text.isNotEmpty ? () => context.push('/bnpl/apply/step2') : null,
            ),
          ],
        ),
      ),
    );
  }
}
