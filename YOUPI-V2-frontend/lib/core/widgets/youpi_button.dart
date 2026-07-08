import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';

enum YoupiButtonType { primary, secondary, ghost }

class YoupiButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final YoupiButtonType type;
  final bool isLoading;
  final Widget? prefixIcon;
  final double? width;
  final double height;

  const YoupiButton({
    super.key,
    required this.label,
    this.onPressed,
    this.type = YoupiButtonType.primary,
    this.isLoading = false,
    this.prefixIcon,
    this.width,
    this.height = AppDimensions.buttonHeight,
  });

  @override
  Widget build(BuildContext context) {
    final isDisabled = onPressed == null && !isLoading;
    return Opacity(
      opacity: isDisabled ? 0.5 : 1.0,
      child: SizedBox(
        width: width ?? double.infinity,
        height: height,
        child: _buildButton(),
      ),
    );
  }

  Widget _buildButton() {
    final child = isLoading
        ? SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: type == YoupiButtonType.primary
                  ? AppColors.backgroundPrimary
                  : AppColors.primary,
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (prefixIcon != null) ...[prefixIcon!, const SizedBox(width: 8)],
              Text(label, style: _labelStyle),
            ],
          );

    switch (type) {
      case YoupiButtonType.primary:
        return ElevatedButton(
          onPressed: isLoading ? null : onPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.backgroundPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
            ),
            elevation: 0,
            shadowColor: AppColors.primaryGlow,
          ),
          child: child,
        );
      case YoupiButtonType.secondary:
        return OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
            ),
          ),
          child: child,
        );
      case YoupiButtonType.ghost:
        return TextButton(
          onPressed: isLoading ? null : onPressed,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
          ),
          child: child,
        );
    }
  }

  TextStyle get _labelStyle {
    switch (type) {
      case YoupiButtonType.primary:
        return AppTextStyles.buttonText;
      case YoupiButtonType.secondary:
        return AppTextStyles.buttonTextOutlined;
      case YoupiButtonType.ghost:
        return AppTextStyles.buttonText.copyWith(color: AppColors.textSecondary);
    }
  }
}
