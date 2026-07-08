import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';

class ShimmerLoader extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerLoader({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = AppDimensions.radiusCard,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.backgroundCard,
      highlightColor: AppColors.divider,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppColors.backgroundCard,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

class ShimmerList extends StatelessWidget {
  final int itemCount;
  final double itemHeight;
  final EdgeInsetsGeometry? padding;

  const ShimmerList({
    super.key,
    this.itemCount = 4,
    this.itemHeight = 80,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.symmetric(horizontal: AppDimensions.paddingPage),
      child: Column(
        children: List.generate(
          itemCount,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: AppDimensions.gapM),
            child: ShimmerLoader(
              width: double.infinity,
              height: itemHeight,
              borderRadius: AppDimensions.radiusCard,
            ),
          ),
        ),
      ),
    );
  }
}

class ShimmerCard extends StatelessWidget {
  const ShimmerCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.backgroundCard,
      highlightColor: AppColors.divider,
      child: Container(
        padding: const EdgeInsets.all(AppDimensions.paddingL),
        decoration: BoxDecoration(
          color: AppColors.backgroundCard,
          borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 16, width: 120, color: AppColors.divider),
            const SizedBox(height: 8),
            Container(height: 32, width: 180, color: AppColors.divider),
            const SizedBox(height: 8),
            Container(height: 12, width: 80, color: AppColors.divider),
          ],
        ),
      ),
    );
  }
}
