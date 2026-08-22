import 'dart:math';
import 'package:flutter/material.dart';

/// YouPi — Full-screen celebration confetti overlay (premium build).
///
/// Two origins on the LEFT and RIGHT edges fire particles radially in all
/// directions; the bursts overlap near the center for a dense, symmetric
/// celebration (matches the "exploding from left and right" reference
/// video).
///
/// PREMIUM PHYSICS (what makes this feel like a polished, Apple-style
/// celebration rather than a basic particle spray):
///  * Air drag        -- particles explode out FAST then decelerate
///                       gracefully (exponential velocity decay), instead
///                       of flying at constant speed. This alone is most
///                       of the "premium" feel.
///  * Terminal velocity -- falling settles to a gentle, constant drift
///                       (like real paper) instead of accelerating
///                       forever under raw gravity.
///  * Paper-flip tumble -- each piece "flips" in 3D (its drawn height
///                       oscillates via |cos|), reading as a real flat
///                       piece of paper turning in the air, not a flat
///                       sticker rotating in 2D.
///  * Falling-leaf sway -- once a piece has slowed, it sways side to
///                       side as it drifts down, like paper actually
///                       falls.
///  * Depth layers     -- each particle has a depth factor scaling its
///                       size/speed/opacity, giving foreground/background
///                       parallax richness.
///  * Double-pop burst -- launches arrive in two quick waves (a main pop
///                       and a smaller follow-up) rather than one flat
///                       spawn window.
///
/// All motion uses closed-form math (no per-frame integration state), so
/// the painter stays cheap: ~650 particles hold 60fps comfortably.
///
/// PERFORMANCE NOTE: an early 4000-particle version was flagged as a
/// jank risk on Tier-2/3 hardware. Density here comes from 650 SMALL
/// pieces + physics richness, not raw count or size. If headroom is
/// needed on a real device, lower [particleCount] first.
class ConfettiBurst extends StatefulWidget {
  final int particleCount;
  final Duration burstDuration; // spawn window for the main pop
  final Duration totalDuration; // fire + flight + fade, then fully stops
  final List<Color> colors;
  final VoidCallback? onFinished;

  const ConfettiBurst({
    super.key,
    this.particleCount = 650,
    this.burstDuration = const Duration(milliseconds: 650),
    this.totalDuration = const Duration(milliseconds: 4200),
    this.colors = const [
      Color(0xFF1CE8A4), // app teal
      Color(0xFFE2A83F), // app amber
      Color(0xFFFF5C7A), // pink
      Color(0xFF5B8DEF), // blue
      Color(0xFFB47CFF), // purple
      Color(0xFFFFFFFF), // white
      Color(0xFF3FE0E0), // cyan
      Color(0xFFFF9F43), // orange
    ],
    this.onFinished,
  });

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _Particle {
  // Origin edge: -1 = left edge, +1 = right edge.
  late double originSign;
  double startT = 0; // 0..1 of totalDuration, when this particle fires

  // Launch, in "screen heights per second".
  double speed = 0;
  double angle = 0; // full 360 radial direction

  // Premium physics parameters.
  double drag = 0;        // per-second exponential velocity decay
  double depth = 1;       // 0.6 (far) .. 1.0 (near): scales size/speed/alpha
  double flip0 = 0;       // paper-flip phase
  double flipSpeed = 0;   // paper-flip rate (rad/sec)
  double swayAmp = 0;     // falling-leaf sway amplitude (screen-height frac)
  double swayFreq = 0;
  double swayPhase = 0;

  double rotation0 = 0;
  double rotSpeed = 0;

  double size = 0;
  double aspect = 1;
  late Color color;
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;
  final _rand = Random();
  bool _finishedCalled = false;

  // Gravity + drag together give a paper-like terminal fall speed of
  // roughly gravity/drag ≈ 0.45 screen-heights/sec.
  static const double _gravity = 1.35; // screen-heights / sec^2

  @override
  void initState() {
    super.initState();
    _particles = _generateParticles();
    _controller = AnimationController(vsync: this, duration: widget.totalDuration)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_finishedCalled) {
          _finishedCalled = true;
          widget.onFinished?.call();
        }
      })
      ..forward();
  }

  List<_Particle> _generateParticles() {
    final burstFraction =
        widget.burstDuration.inMilliseconds / widget.totalDuration.inMilliseconds;

    return List.generate(widget.particleCount, (i) {
      final p = _Particle();
      p.originSign = (i.isEven) ? -1.0 : 1.0;

      // Double-pop: ~70% of pieces in the main pop, ~30% in a smaller
      // follow-up wave shortly after -- reads as a lively "pop..pop!"
      // rather than a single flat spawn.
      if (_rand.nextDouble() < 0.7) {
        p.startT = _rand.nextDouble() * burstFraction * 0.55;
      } else {
        p.startT = burstFraction * (0.65 + _rand.nextDouble() * 0.45);
      }

      p.angle = _rand.nextDouble() * 2 * pi;

      // Depth layer: far pieces are smaller, a bit slower, slightly
      // transparent; near pieces are full size/speed/opacity.
      p.depth = 0.6 + _rand.nextDouble() * 0.4;

      // Launch fast -- drag will bleed this off quickly, which is what
      // produces the "explode then float" premium arc.
      p.speed = (1.6 + _rand.nextDouble() * 1.6) * p.depth;
      p.drag = 2.6 + _rand.nextDouble() * 1.4; // /sec

      p.rotation0 = _rand.nextDouble() * 2 * pi;
      p.rotSpeed = (_rand.nextDouble() - 0.5) * 10;

      p.flip0 = _rand.nextDouble() * 2 * pi;
      p.flipSpeed = 5 + _rand.nextDouble() * 9;

      p.swayAmp = 0.008 + _rand.nextDouble() * 0.02;
      p.swayFreq = 1.6 + _rand.nextDouble() * 2.2;
      p.swayPhase = _rand.nextDouble() * 2 * pi;

      p.size = (5 + _rand.nextDouble() * 6) * p.depth;

      final shapeRoll = _rand.nextDouble();
      if (shapeRoll < 0.45) {
        p.aspect = 0.9 + _rand.nextDouble() * 0.3;   // squares
      } else if (shapeRoll < 0.8) {
        p.aspect = 1.4 + _rand.nextDouble() * 0.8;   // rectangles
      } else {
        p.aspect = 3.0 + _rand.nextDouble() * 2.2;   // ribbon strips
      }

      p.color = widget.colors[_rand.nextInt(widget.colors.length)];
      return p;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            painter: _ConfettiPainter(
              particles: _particles,
              t: _controller.value,
              totalSeconds: widget.totalDuration.inMilliseconds / 1000.0,
              gravity: _gravity,
            ),
            size: Size.infinite,
          );
        },
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  final List<_Particle> particles;
  final double t;
  final double totalSeconds;
  final double gravity;

  _ConfettiPainter({
    required this.particles,
    required this.t,
    required this.totalSeconds,
    required this.gravity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final h = size.height;
    final w = size.width;

    const originYFrac = 0.42;

    for (final p in particles) {
      if (t < p.startT) continue;

      final localFrac = ((t - p.startT) / (1 - p.startT)).clamp(0.0, 1.0);
      final life = (1 - p.startT) * totalSeconds;
      final dt = localFrac * life;

      final vx0 = sin(p.angle) * p.speed;
      final vy0 = -cos(p.angle) * p.speed;

      // ── Drag physics, closed form ──
      // Horizontal: pure exponential decay of velocity.
      //   x(t) = x0 + vx0/k * (1 - e^(-k t))
      // Vertical: gravity + drag -> settles to terminal velocity vT = g/k.
      //   y(t) = y0 + vT*t + (vy0 - vT)/k * (1 - e^(-k t))
      final k = p.drag;
      final decay = 1 - exp(-k * dt);
      final vT = gravity / k; // terminal fall speed (screen-heights/sec)

      // Falling-leaf sway: negligible while the piece is still moving
      // fast (early flight), grows as it slows into its drift-down phase.
      final settle = (1 - exp(-k * dt)); // 0 -> 1 as launch energy bleeds off
      final sway = sin(dt * p.swayFreq * 2 * pi + p.swayPhase) * p.swayAmp * settle;

      final xFrac = (p.originSign < 0 ? 0.0 : 1.0) + (vx0 / k) * decay + sway;
      final yFrac = originYFrac + vT * dt + ((vy0 - vT) / k) * decay;

      // Fade over the last 40% of life; hard-cut once off-screen.
      double opacity =
      localFrac > 0.6 ? (1 - (localFrac - 0.6) / 0.4).clamp(0.0, 1.0) : 1.0;
      if (yFrac > 1.05 || yFrac < -0.15 || xFrac < -0.15 || xFrac > 1.15) {
        opacity = 0;
      }
      if (opacity <= 0) continue;

      // Depth layer alpha: far pieces sit a touch more transparent.
      opacity *= 0.7 + 0.3 * p.depth;

      // Paper-flip: drawn height oscillates through |cos| -- the piece
      // appears to turn over in 3D. Clamped so it never vanishes fully.
      final flip = cos(p.flip0 + p.flipSpeed * dt).abs().clamp(0.18, 1.0);

      final dx = xFrac * w;
      final dy = yFrac * h;

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(p.rotation0 + p.rotSpeed * dt);
      paint.color = p.color.withOpacity(opacity);

      final pw = p.size;
      final ph = (p.size / p.aspect) * flip;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: pw, height: ph),
        Radius.circular(min(pw, ph) * 0.25),
      );
      canvas.drawRRect(rrect, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}