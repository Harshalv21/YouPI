import 'package:flutter/material.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';

/// Wraps any widget to show it as locked/"Coming Soon".
///
/// Security note: this does NOT just dim the UI — the overlay's
/// GestureDetector sits on top and consumes every tap in that area, so the
/// wrapped child's own onTap/navigation NEVER fires. A locked feature is
/// genuinely unreachable, not just visually discouraged. That matters for
/// fintech: a half-built or not-yet-audited endpoint (e.g. one still pending
/// a security fix) should be impossible to reach by accident, not just
/// "hidden" behind a greyed-out look a curious tap could still trigger.
class ComingSoonOverlay extends StatelessWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final BoxShape shape;
  final double iconSize;
  final bool showLabel;
  // When false, this is purely a visual lock (dark overlay + icon) with no
  // GestureDetector of its own -- use this when a parent widget already
  // owns the tap handling (e.g. a quick-action tile where the whole
  // icon+label column shares one tap target) so taps aren't consumed twice.
  final bool interactive;

  const ComingSoonOverlay({
    super.key,
    required this.child,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    this.iconSize = 20,
    this.showLabel = true,
    this.interactive = true,
  });

  @override
  Widget build(BuildContext context) {
    final radius =
    shape == BoxShape.circle ? null : (borderRadius ?? BorderRadius.circular(AppDimensions.radiusCard));

    final overlay = Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        shape: shape,
        borderRadius: radius,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_rounded, color: Colors.white.withOpacity(0.95), size: iconSize),
          if (showLabel) ...[
            const SizedBox(height: 4),
            Text(
              'Coming Soon',
              style: AppTextStyles.labelSmall.copyWith(
                color: Colors.white.withOpacity(0.95),
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );

    return Stack(
      children: [
        child,
        Positioned.fill(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) => Opacity(
              opacity: t,
              child: Transform.scale(scale: 0.9 + (0.1 * t), child: _),
            ),
            child: interactive
                ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Coming soon — this feature isn't live yet."),
                  backgroundColor: AppColors.backgroundCard,
                ),
              ),
              child: overlay,
            )
                : IgnorePointer(child: overlay),
          ),
        ),
      ],
    );
  }
}