import 'package:flutter/material.dart';
import 'package:pin_code_fields/pin_code_fields.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

class OtpInputField extends StatelessWidget {
  final void Function(String)? onCompleted;
  final void Function(String)? onChanged;
  final TextEditingController? controller;
  final int length;

  const OtpInputField({
    super.key,
    this.onCompleted,
    this.onChanged,
    this.controller,
    this.length = 6,
  });

  @override
  Widget build(BuildContext context) {
    return PinCodeTextField(
      appContext: context,
      length: length,
      controller: controller,
      onCompleted: onCompleted,
      onChanged: onChanged ?? (_) {},
      keyboardType: TextInputType.number,
      animationType: AnimationType.fade,
      pinTheme: PinTheme(
        shape: PinCodeFieldShape.box,
        borderRadius: BorderRadius.circular(10),
        fieldHeight: 52,
        fieldWidth: 48,
        activeFillColor: AppColors.primary,
        inactiveFillColor: AppColors.backgroundCard,
        selectedFillColor: AppColors.backgroundCard,
        activeColor: AppColors.primary,
        inactiveColor: AppColors.divider,
        selectedColor: AppColors.primary,
      ),
      enableActiveFill: true,
      textStyle: AppTextStyles.headlineSmall.copyWith(
        color: AppColors.backgroundPrimary,
      ),
      backgroundColor: Colors.transparent,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    );
  }
}
