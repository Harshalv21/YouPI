import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';

class YoupiCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? backgroundColor;
  final bool showGlow;
  final VoidCallback? onTap;
  final double borderRadius;
  final Color? borderColor;
  final List<BoxShadow>? shadows;

  const YoupiCard({
    super.key,
    required this.child,
    this.padding,
    this.backgroundColor,
    this.showGlow = false,
    this.onTap,
    this.borderRadius = AppDimensions.radiusCard,
    this.borderColor,
    this.shadows,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: padding ?? const EdgeInsets.all(AppDimensions.paddingL),
        decoration: BoxDecoration(
          color: backgroundColor ?? AppColors.backgroundCard,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: borderColor ?? (showGlow ? AppColors.primary : AppColors.divider),
            width: showGlow ? 1.5 : 1,
          ),
          boxShadow: shadows ??
              (showGlow
                  ? [
                      BoxShadow(
                        color: AppColors.primaryGlow,
                        blurRadius: 20,
                        spreadRadius: 0,
                      )
                    ]
                  : null),
        ),
        child: child,
      ),
    );
  }
}

class YoupiGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const YoupiGlassCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(AppDimensions.paddingL),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.backgroundSurface,
            AppColors.backgroundCard,
          ],
        ),
        borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
        border: Border.all(color: AppColors.primary.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGlow,
            blurRadius: 20,
          ),
        ],
      ),
      child: child,
    );
  }
}
