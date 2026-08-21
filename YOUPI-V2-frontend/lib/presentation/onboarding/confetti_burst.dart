import 'dart:math';
import 'package:flutter/material.dart';

/// YouPi — Full-screen celebration confetti overlay.
///
/// Matches the reference "cannon" style burst: particles launch from the
/// BOTTOM-LEFT and BOTTOM-RIGHT corners, fly upward and inward under real
/// projectile physics (initial velocity + constant gravity), tumble as
/// they fly, arc over, and fall back down / off-screen while fading out.
///
/// Rebuilt as a plain CustomPainter (no external package) so colors/shapes
/// match the app palette exactly and there's no plugin overhead.
///
/// PERFORMANCE NOTE: an earlier version of this widget used 4000
/// simultaneous particles and was flagged in QA as a jank risk on
/// Tier-2/3 hardware. This version uses real two-origin trajectories
/// instead of raw particle count to sell the "explosion" feeling, so the
/// default count is much lower (260 total / 130 per corner) while still
/// reading as a dense, premium burst. If it still needs headroom on real
/// devices, lower [particleCount] further rather than re-adding a
/// package dependency.
class ConfettiBurst extends StatefulWidget {
  final int particleCount;
  final Duration burstDuration; // how long each cannon keeps firing
  final Duration totalDuration; // fire + flight + fade, then fully stops
  final List<Color> colors;
  final VoidCallback? onFinished;

  const ConfettiBurst({
    super.key,
    this.particleCount = 260,
    this.burstDuration = const Duration(milliseconds: 650),
    this.totalDuration = const Duration(milliseconds: 3600),
    this.colors = const [
      Color(0xFF1CE8A4), // app teal
      Color(0xFFE2A83F), // app amber
      Color(0xFFFF5C7A), // pink
      Color(0xFF5B8DEF), // blue
      Color(0xFFB47CFF), // purple
      Color(0xFFFFFFFF), // white
    ],
    this.onFinished,
  });

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

enum _ParticleShape { square, rect, strip }

class _Particle {
  // Origin corner: -1 = bottom-left, +1 = bottom-right.
  late double originSign;
  double startT = 0; // 0..1, when this particle fires within totalDuration

  // Launch physics, in "screen heights per second" units so it scales
  // cleanly to any device size regardless of pixel density.
  double speed = 0; // initial launch speed
  double angle = 0; // launch angle in radians, measured from straight up

  double rotation0 = 0;
  double rotSpeed = 0; // radians/sec, natural tumble
  double wobbleAmp = 0; // small horizontal sway while airborne
  double wobbleFreq = 0;

  double size = 0;
  double aspect = 1; // width:height ratio for rect/strip variety
  late Color color;
  late _ParticleShape shape;
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;
  final _rand = Random();
  bool _finishedCalled = false;

  static const double _gravity = 2.6; // screen-heights / sec^2

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
      // Split evenly between the two corners.
      p.originSign = (i.isEven) ? -1.0 : 1.0;

      // Staggered launch -> reads as a rapid-fire cannon burst rather
      // than one single flat explosion frame.
      p.startT = _rand.nextDouble() * burstFraction;

      // Launch mostly upward, angled inward toward center, with spread.
      // 0 rad = straight up. Positive rotates toward center.
      final inwardBase = 22 * pi / 180; // aim ~22deg in from vertical
      final spread = (_rand.nextDouble() - 0.5) * 34 * pi / 180; // +-17deg
      p.angle = inwardBase + spread;

      p.speed = 1.15 + _rand.nextDouble() * 0.85; // screen-heights/sec
      p.rotation0 = _rand.nextDouble() * 2 * pi;
      p.rotSpeed = (_rand.nextDouble() - 0.5) * 12;
      p.wobbleAmp = 0.01 + _rand.nextDouble() * 0.02;
      p.wobbleFreq = 2 + _rand.nextDouble() * 3;

      p.size = 6 + _rand.nextDouble() * 7;
      p.color = widget.colors[_rand.nextInt(widget.colors.length)];

      final shapeRoll = _rand.nextDouble();
      if (shapeRoll < 0.4) {
        p.shape = _ParticleShape.square;
        p.aspect = 0.85 + _rand.nextDouble() * 0.3;
      } else if (shapeRoll < 0.75) {
        p.shape = _ParticleShape.rect;
        p.aspect = 1.4 + _rand.nextDouble() * 0.8;
      } else {
        p.shape = _ParticleShape.strip;
        p.aspect = 3.2 + _rand.nextDouble() * 2.2; // elongated ribbon piece
      }
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
  final double t; // 0..1 overall progress
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

    for (final p in particles) {
      if (t < p.startT) continue; // hasn't fired yet

      // Local elapsed time (seconds) since this particle launched.
      final localFrac = ((t - p.startT) / (1 - p.startT)).clamp(0.0, 1.0);
      final life = (1 - p.startT) * totalSeconds; // this particle's lifespan
      final dt = localFrac * life; // seconds since launch

      // Projectile motion: origin at bottom-left/right, launch angle
      // measured from straight up, gravity pulls down over time.
      final vx0 = p.originSign * sin(p.angle) * p.speed;
      final vy0 = -cos(p.angle) * p.speed; // negative = upward

      final wobble = sin(dt * p.wobbleFreq) * p.wobbleAmp;
      final xFrac = (p.originSign < 0 ? 0.0 : 1.0) + vx0 * dt + wobble;
      final yFrac = 1.0 + vy0 * dt + 0.5 * gravity * dt * dt;

      // Fade in the last 35% of life, or immediately once off-screen.
      double opacity = localFrac > 0.65 ? (1 - (localFrac - 0.65) / 0.35).clamp(0.0, 1.0) : 1.0;
      if (yFrac > 1.05 || yFrac < -0.15 || xFrac < -0.15 || xFrac > 1.15) {
        opacity = 0;
      }
      if (opacity <= 0) continue;

      final dx = xFrac * w;
      final dy = yFrac * h;

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(p.rotation0 + p.rotSpeed * dt);
      paint.color = p.color.withOpacity(opacity);

      final width = p.size;
      final height = p.size / p.aspect;
      final rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: width, height: height),
        Radius.circular(min(width, height) * 0.2),
      );
      canvas.drawRRect(rrect, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}
