import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';

/// Wraps any widget to show it as locked/"Coming Soon".
///
/// Security note: this does NOT just dim the UI — the overlay's
/// GestureDetector sits on top and consumes every tap in that area, so the
/// wrapped child's own onTap/navigation NEVER fires. A locked feature is
/// genuinely unreachable, not just visually discouraged.
///
/// Pure UI/presentation — no auth-state branching, so the same look and
/// tap-behavior apply identically for a registered user, a logged-in user,
/// and a guest.
///
/// Design: no lock icon anywhere -- just a dimmed overlay with a glowing,
/// gently-blinking "Coming Soon" label (neon-sign style) where [showLabel]
/// is true. Tapping shows a quick bottom SnackBar with a randomly varied
/// message that clears fast.
class ComingSoonOverlay extends StatefulWidget {
  final Widget child;
  final BorderRadius? borderRadius;
  final BoxShape shape;
  final double iconSize; // kept for API compatibility; unused (no icon)
  final bool showLabel;
  final bool interactive;

  // Where the "Coming Soon" label sits within the overlay. Defaults to
  // dead-center (existing behavior for quick actions / portfolio metrics).
  // Pass e.g. Alignment(0.6, -0.6) to push it up-and-right, near a corner
  // control like an eye-toggle icon.
  final Alignment labelAlignment;
  // Font size for the label. Defaults to 22 (existing behavior).
  final double labelFontSize;

  const ComingSoonOverlay({
    super.key,
    required this.child,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    this.iconSize = 20,
    this.showLabel = true,
    this.interactive = true,
    this.labelAlignment = Alignment.center,
    this.labelFontSize = 22,
  });

  static const List<String> _snackMessages = [
    "✨ Coming soon — stay tuned!",
    "🚀 This one's on the way!",
    "🔒 Not live yet — almost there!",
  ];

  /// Shared so other widgets (e.g. a parent tile that owns its own tap
  /// handling) can trigger the exact same message.
  static void showComingSoonSnack(BuildContext context) {
    HapticFeedback.lightImpact();
    final message = (List<String>.from(_snackMessages)..shuffle()).first;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
        ),
        backgroundColor: AppColors.backgroundCard,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: AppColors.secondary.withOpacity(0.3)),
        ),
        // Clears quickly after each tap rather than lingering.
        duration: const Duration(milliseconds: 1400),
      ),
    );
  }

  /// Same message pool as [showComingSoonSnack], but rendered as a
  /// self-dismissing banner near the TOP of the screen via the app's ROOT
  /// overlay instead of a bottom SnackBar.
  ///
  /// Use this instead of [showComingSoonSnack] whenever the caller might be
  /// underneath a modal barrier -- e.g. a button inside a `showDialog(...)`
  /// popup. A SnackBar there calls `ScaffoldMessenger.of(context)`, which
  /// walks UP the tree past the Dialog to the nearest real Scaffold
  /// (usually the page behind the dialog) and renders at ITS bottom --
  /// which sits BELOW the dialog's own barrier in the Overlay stack, so it
  /// shows up dim and half-hidden at the bottom of a screen the user can't
  /// even see yet. Inserting into `rootOverlay: true` instead guarantees
  /// this renders above every barrier/dialog currently on screen, same
  /// architecture as showGoldCoinReward's overlay in
  /// gold_coin_reward_screen.dart.
  static void showComingSoonTopBanner(BuildContext context) {
    HapticFeedback.lightImpact();
    final message = (List<String>.from(_snackMessages)..shuffle()).first;
    final overlayState = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;
    var removed = false;
    void remove() {
      if (removed) return;
      removed = true;
      entry.remove();
    }

    entry = OverlayEntry(
      builder: (ctx) => _ComingSoonTopBanner(message: message, onDone: remove),
    );
    overlayState.insert(entry);
  }

  @override
  State<ComingSoonOverlay> createState() => ComingSoonOverlayState();
}

class _ComingSoonTopBanner extends StatefulWidget {
  final String message;
  final VoidCallback onDone;
  const _ComingSoonTopBanner({required this.message, required this.onDone});

  @override
  State<_ComingSoonTopBanner> createState() => _ComingSoonTopBannerState();
}

class _ComingSoonTopBannerState extends State<_ComingSoonTopBanner> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    // Enter on next frame (lets the slide-in transition actually animate
    // from off-screen instead of popping in already at Offset.zero).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _visible = true);
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (!mounted) return;
        setState(() => _visible = false);
        Future.delayed(const Duration(milliseconds: 300), widget.onDone);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: IgnorePointer(
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 300),
            curve: _visible ? Curves.easeOutBack : Curves.easeInCubic,
            offset: _visible ? Offset.zero : const Offset(0, -1.4),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: _visible ? 1.0 : 0.0,
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.backgroundCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.secondary.withOpacity(0.3)),
                  ),
                  child: Text(
                    widget.message,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ComingSoonOverlayState extends State<ComingSoonOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _blinkController;
  late final Animation<double> _blinkAnimation;

  static const _normalBlink = Duration(milliseconds: 1100);
  static const _fastBlink = Duration(milliseconds: 500);
  bool _spedUp = false;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: _normalBlink,
    )..repeat(reverse: true);
    _blinkAnimation = Tween<double>(begin: 0.45, end: 1.0).animate(
      CurvedAnimation(parent: _blinkController, curve: Curves.easeInOut),
    );
  }

  // Called once, the first time the overlay is tapped -- speeds up the
  // blink permanently for this widget instance.
  void triggerFastBlink() {
    if (_spedUp) return;
    _spedUp = true;
    _blinkController.duration = _fastBlink;
    _blinkController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.shape == BoxShape.circle
        ? null
        : (widget.borderRadius ?? BorderRadius.circular(AppDimensions.radiusCard));

    final overlay = Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.55),
        shape: widget.shape,
        borderRadius: radius,
      ),
      child: widget.showLabel
          ? Align(
        alignment: widget.labelAlignment,
        child: AnimatedBuilder(
          animation: _blinkAnimation,
          builder: (context, _) => Opacity(
            opacity: _blinkAnimation.value,
            // Neon-sign look: the fill color plus several
            // increasingly-blurred shadow layers in the same color
            // stacked on top of each other, so the glow spreads
            // outward from the letterforms like a lit-up sign.
            // Wrapped in Padding + FittedBox so it auto-shrinks to fit
            // tiny containers (e.g. the 52px quick-action circles)
            // without overflowing.
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Coming Soon',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: widget.labelFontSize,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    height: 1.05,
                    color: AppColors.secondary,
                    shadows: [
                      Shadow(color: AppColors.secondary, blurRadius: 6),
                      Shadow(color: AppColors.secondary, blurRadius: 14),
                      Shadow(color: AppColors.secondary.withOpacity(0.85), blurRadius: 26),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      )
          : null,
    );

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) => Opacity(
              opacity: t,
              child: Transform.scale(scale: 0.9 + (0.1 * t), child: _),
            ),
            child: widget.interactive
                ? GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                triggerFastBlink();
                ComingSoonOverlay.showComingSoonSnack(context);
              },
              child: overlay,
            )
                : IgnorePointer(child: overlay),
          ),
        ),
      ],
    );
  }
}