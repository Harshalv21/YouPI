import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';

/// Shows the coin-toss reward as an overlay, then has the coin FLY across
/// the screen to land on Home's header badge -- continuing to animate
/// visibly on top of Home's real content, not just fading out before the
/// navigation happens.
///
/// KEY ARCHITECTURE POINT: this only works because the OverlayEntry is
/// inserted into the app's ROOT overlay (`rootOverlay: true`), which is
/// independent of the Navigator/route stack. Route changes underneath
/// (Confirm Recharge -> Home) do NOT remove or interrupt this overlay --
/// it keeps rendering and animating straight through the navigation. That
/// means `onNavigateHome` can fire mid-animation (right as the exit/fly
/// phase begins) while the coin keeps flying, now visibly over Home's
/// real content, until it reaches the target position -- THEN the
/// overlay removes itself, timed to hand off to Home's own badge pop-in.
///
/// Usage (see emi_selection_screen.dart -- API changed from before):
///   await showGoldCoinReward(
///     context,
///     plan.price,
///     onNavigateHome: () => context.go('/dashboard/home', extra: {'justEarnedCoin': true}),
///   );
/// Do NOT call context.go(...) again after this returns -- navigation
/// already happened inside, at the correct moment in the animation.
Future<void> showGoldCoinReward(
    BuildContext context,
    double rechargeAmount, {
      required VoidCallback onNavigateHome,
    }) {
  final completer = Completer<void>();
  late final OverlayEntry entry;
  var removed = false;

  void removeEntry() {
    if (removed) return;
    removed = true;
    entry.remove();
    if (!completer.isCompleted) completer.complete();
  }

  entry = OverlayEntry(
    builder: (_) => _GoldCoinRewardOverlay(
      rechargeAmount: rechargeAmount,
      onNavigateHome: onNavigateHome,
      onDone: removeEntry,
    ),
  );

  Overlay.of(context, rootOverlay: true).insert(entry);
  return completer.future;
}

class _GoldCoinRewardOverlay extends StatefulWidget {
  final double rechargeAmount;
  final VoidCallback onNavigateHome;
  final VoidCallback onDone;
  const _GoldCoinRewardOverlay({
    required this.rechargeAmount,
    required this.onNavigateHome,
    required this.onDone,
  });

  @override
  State<_GoldCoinRewardOverlay> createState() => _GoldCoinRewardOverlayState();
}

class _GoldCoinRewardOverlayState extends State<_GoldCoinRewardOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Sparkle> _sparkles;
  final _audioPlayer = AudioPlayer();

  // Timeline (fractions of total duration):
  //   0.00 - 0.28  rise (spin up, lift from center)
  //   0.28 - 0.55  fall + gravity bounce, settles at center
  //   0.55 - 0.75  hold at center, success text shows, sparkles swirl
  //   0.75         <-- navigation to Home fires HERE, coin keeps flying
  //   0.75 - 1.00  fly to top-right (now visibly over Home's content)
  static const _totalDuration = Duration(milliseconds: 3200);
  static const _riseEnd = 0.28;
  static const _fallEnd = 0.55;
  static const _holdEnd = 0.75;

  bool _closing = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _totalDuration);
    _sparkles = List.generate(26, (i) => _Sparkle(i));

    _controller.forward();
    _audioPlayer.play(AssetSource('sounds/recharge_success.mp3')).catchError((_) {});

    _controller.addListener(() {
      // Fire navigation exactly once, right as the fly-to-badge phase
      // begins -- the coin then keeps animating on top of whatever
      // screen GoRouter swaps in underneath (Home), since this overlay
      // lives on the root Overlay, independent of that route change.
      if (!_navigated && _controller.value >= _holdEnd) {
        _navigated = true;
        if (mounted) widget.onNavigateHome();
      }
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Small settle pause once it "lands" on the badge before
        // removing -- Home's own badge pop-in (see home_screen.dart)
        // should feel like a continuation, not a jarring cut.
        Future.delayed(const Duration(milliseconds: 150), _close);
      }
    });
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _controller.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  double get _valueEarned => widget.rechargeAmount * 0.01;

  double _coinYOffset(double t) {
    if (t < _riseEnd) {
      final localT = t / _riseEnd;
      final eased = Curves.easeOut.transform(localT);
      return -70 * eased;
    } else if (t < _fallEnd) {
      final localT = (t - _riseEnd) / (_fallEnd - _riseEnd);
      if (localT < 0.75) {
        final fallT = localT / 0.75;
        final eased = Curves.easeIn.transform(fallT);
        return -70 + 95 * eased;
      } else {
        final bounceT = (localT - 0.75) / 0.25;
        final eased = Curves.easeOut.transform(bounceT);
        return 25 - 25 * eased;
      }
    } else if (t < _holdEnd) {
      final idleT = (t - _fallEnd) / (_holdEnd - _fallEnd);
      return math.sin(idleT * math.pi * 4) * 2.5;
    }
    return 0;
  }

  double _coinSpin(double t) {
    if (t < _fallEnd) {
      return t * 10 * math.pi;
    } else if (t < _holdEnd) {
      final localT = (t - _fallEnd) / (_holdEnd - _fallEnd);
      final spinAtSettle = _fallEnd * 10 * math.pi;
      return spinAtSettle + (1 - localT) * 0.3 * math.sin(localT * math.pi * 2);
    } else {
      // Continues spinning (slowing down) during the fly-to-badge phase --
      // matches the reference: it's still visibly a spinning coin while
      // in flight, not a static shrinking dot.
      final flyT = (t - _holdEnd) / (1.0 - _holdEnd);
      final spinAtHoldEnd = _fallEnd * 10 * math.pi;
      return spinAtHoldEnd + flyT * 4 * math.pi;
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final center = Offset(size.width / 2, size.height / 2);
    // Approximate position of Home's header coin icon (top-right, near
    // the "Welcome back" row). May need small manual tuning once you see
    // it against the real device/screen size -- this is a fixed estimate,
    // not read from the actual widget (Home isn't mounted yet when this
    // animation starts, and by the time it is, this overlay is already
    // independent of it).
    final badgeTarget = Offset(size.width - 55, 95);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;

        Offset coinPos;
        double coinScale;
        double coinOpacity;
        // Barrier only during rise/fall/hold -- once flying to the badge
        // (now over Home's real content), the barrier must be gone so
        // Home is fully visible, not dimmed, while the coin completes
        // its flight on top of it.
        double barrierOpacity;

        if (t < _holdEnd) {
          coinPos = center + Offset(0, _coinYOffset(t));
          coinScale = t < 0.06 ? (t / 0.06).clamp(0.0, 1.0) : 1.0;
          coinOpacity = 1.0;
          barrierOpacity = t < 0.06 ? (t / 0.06).clamp(0.0, 1.0) * 0.55 : 0.55;
        } else {
          final flyT = ((t - _holdEnd) / (1.0 - _holdEnd)).clamp(0.0, 1.0);
          final eased = Curves.easeInOutCubic.transform(flyT);
          coinPos = Offset.lerp(center, badgeTarget, eased)!;
          coinScale = 1.0 - eased * 0.65; // shrinks toward badge size, not to nothing
          coinOpacity = 1.0;
          // Barrier fades out quickly right as flight begins -- Home
          // needs to be fully visible underneath for this beat to read
          // correctly (matches the reference: no dimming during the fly).
          barrierOpacity = (0.55 * (1 - (flyT / 0.15).clamp(0.0, 1.0)));
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: IgnorePointer(
                ignoring: t >= _holdEnd, // let Home's own UI be interactive again once flying over it
                child: GestureDetector(
                  // Lets an impatient user skip straight past the
                  // rise/fall/hold beat -- never trap someone in a forced
                  // animation on a real-money screen. Only active before
                  // the fly-to-badge phase starts (matches the ignoring
                  // condition above); once flying, tapping Home's real UI
                  // underneath should do whatever THAT normally does, not
                  // skip this animation.
                  onTap: () {
                    if (!_navigated) {
                      _navigated = true;
                      widget.onNavigateHome();
                    }
                    _close();
                  },
                  child: Container(color: Colors.black.withOpacity(barrierOpacity)),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _SparklePainter(sparkles: _sparkles, t: t, coinCenter: coinPos),
              ),
            ),
            _buildCoin(coinPos, coinScale, coinOpacity, _coinSpin(t)),
            if (t < _holdEnd) _buildText(t, center),
          ],
        );
      },
    );
  }

  Widget _buildCoin(Offset pos, double scale, double opacity, double spin) {
    return Positioned(
      left: pos.dx - 55,
      top: pos.dy - 55,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale.clamp(0.0, 1.0),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.003)
                ..rotateY(spin),
              child: SizedBox(
                width: 110,
                height: 110,
                child: Image.asset(
                  'assets/images/youpi_coin.png',
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle),
                    child: const Icon(Icons.monetization_on_rounded, color: Colors.black, size: 60),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildText(double t, Offset center) {
    if (t < _fallEnd) return const SizedBox.shrink();
    final localT = ((t - _fallEnd) / (_holdEnd - _fallEnd)).clamp(0.0, 1.0);

    return Positioned(
      top: center.dy + 85,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: Opacity(
          opacity: localT,
          child: Transform.translate(
            offset: Offset(0, (1 - localT) * 10),
            child: Column(
              children: [
                Text('You earned 1 YouPi Coin!',
                    style: AppTextStyles.headlineSmall.copyWith(
                      color: AppColors.secondary,
                      shadows: const [Shadow(color: Colors.black87, blurRadius: 8)],
                    ),
                    textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text('Worth ₹${_valueEarned.toStringAsFixed(2)}',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: Colors.white70,
                      shadows: const [Shadow(color: Colors.black87, blurRadius: 6)],
                    )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Sparkle {
  final double angleOffset;
  final double orbitRadius;
  final double spawnDelay;
  final double lifeSpan;
  final double size;
  final double rotationSpeed;
  final Color color;

  _Sparkle(int seed)
      : angleOffset = (seed * 2.4) % (2 * math.pi),
        orbitRadius = 55 + (seed * 7 % 55).toDouble(),
        spawnDelay = (seed % 10) / 22.0,
        lifeSpan = 0.35 + (seed % 5) / 20.0,
        size = 5 + (seed % 4).toDouble() * 1.6,
        rotationSpeed = 2.5 + (seed % 3),
        color = [
          const Color(0xFFFFD700),
          const Color(0xFFFFF3B0),
          const Color(0xFFFFFFFF),
          const Color(0xFFFFC94A),
        ][seed % 4];
}

class _SparklePainter extends CustomPainter {
  final List<_Sparkle> sparkles;
  final double t;
  final Offset coinCenter;

  _SparklePainter({required this.sparkles, required this.t, required this.coinCenter});

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in sparkles) {
      final localT = ((t - s.spawnDelay) / s.lifeSpan).clamp(0.0, 1.0);
      if (t < s.spawnDelay || localT >= 1.0) continue;

      final angle = s.angleOffset + t * s.rotationSpeed * 2 * math.pi;
      final radius = s.orbitRadius * (0.6 + localT * 0.6);
      final pos = coinCenter + Offset(math.cos(angle) * radius, math.sin(angle) * radius * 0.6);

      final opacity = localT < 0.2
          ? localT / 0.2
          : localT > 0.7
          ? (1 - (localT - 0.7) / 0.3)
          : 1.0;

      _drawSparkle(canvas, pos, s.size * (0.5 + localT * 0.5), angle * 2, s.color.withOpacity(opacity.clamp(0.0, 1.0)));
    }
  }

  void _drawSparkle(Canvas canvas, Offset center, double size, double rotation, Color color) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);

    final path = Path();
    final long = size * 2.2;
    final short = size * 0.55;
    path.moveTo(0, -long);
    path.quadraticBezierTo(short * 0.3, -short * 0.3, long, 0);
    path.quadraticBezierTo(short * 0.3, short * 0.3, 0, long);
    path.quadraticBezierTo(-short * 0.3, short * 0.3, -long, 0);
    path.quadraticBezierTo(-short * 0.3, -short * 0.3, 0, -long);
    path.close();

    canvas.drawPath(path, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) => oldDelegate.t != t;
}