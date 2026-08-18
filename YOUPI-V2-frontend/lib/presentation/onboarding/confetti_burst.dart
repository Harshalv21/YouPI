import 'dart:math';
import 'package:flutter/material.dart';

/// YouPi — Confetti burst overlay.
///
/// A short, high-density confetti burst that plays once and stops on its
/// own. Built as a plain CustomPainter (no external package dependency)
/// so colors/shape match the app's palette exactly.
///
/// PERFORMANCE NOTE: [particleCount] defaults to 4000, per explicit
/// request. This is a LOT of simultaneous canvas draw calls per frame —
/// fine on most devices for a short burst, but YouPi's audience skews
/// Tier 2/3 with lower-end phones, so watch for jank on real devices
/// during QA. If you see dropped frames, the cheapest fix is lowering
/// this constant (2000 still reads as "a lot" visually) rather than
/// re-architecting the painter.
class ConfettiBurst extends StatefulWidget {
  final int particleCount;
  final Duration burstDuration; // how long particles keep spawning
  final Duration totalDuration; // spawning + falling + fade, then stops
  final List<Color> colors;

  const ConfettiBurst({
    super.key,
    this.particleCount = 4000,
    this.burstDuration = const Duration(milliseconds: 1400),
    this.totalDuration = const Duration(milliseconds: 4200),
    this.colors = const [
      Color(0xFF1CE8A4), // app teal
      Color(0xFFE2A83F), // app amber
      Color(0xFFFF5C7A), // pink
      Color(0xFF5B8DEF), // blue
      Color(0xFFB47CFF), // purple
      Color(0xFFFFFFFF), // white
    ],
  });

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();
}

class _Particle {
  double x = 0;       // 0..1, fraction of width
  double startT = 0;  // 0..1, when this particle spawns within totalDuration
  double fallSpeed = 0;
  double drift = 0;
  double rotSpeed = 0;
  double size = 0;
  late Color color;
  bool isStrip = false; // rect vs thin ribbon shape, matches reference art
}

class _ConfettiBurstState extends State<ConfettiBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;
  final _rand = Random();

  @override
  void initState() {
    super.initState();
    _particles = _generateParticles();
    _controller = AnimationController(vsync: this, duration: widget.totalDuration)
      ..forward();
  }

  List<_Particle> _generateParticles() {
    final burstFraction =
        widget.burstDuration.inMilliseconds / widget.totalDuration.inMilliseconds;
    return List.generate(widget.particleCount, (_) {
      final p = _Particle();
      p.x = _rand.nextDouble();
      // Spawn staggered across the burst window -> reads as "continuously
      // bursting for a bit" rather than one single flat explosion frame.
      p.startT = _rand.nextDouble() * burstFraction;
      p.fallSpeed = 0.35 + _rand.nextDouble() * 0.5;
      p.drift = (_rand.nextDouble() - 0.5) * 0.4;
      p.rotSpeed = (_rand.nextDouble() - 0.5) * 10;
      p.size = 5 + _rand.nextDouble() * 6;
      p.color = widget.colors[_rand.nextInt(widget.colors.length)];
      p.isStrip = _rand.nextBool();
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

  _ConfettiPainter({required this.particles, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      if (t < p.startT) continue; // hasn't spawned yet
      final localT = ((t - p.startT) / (1 - p.startT)).clamp(0.0, 1.0);

      // Fade out over the last 30% of each particle's own lifetime.
      final opacity = localT > 0.7 ? (1 - (localT - 0.7) / 0.3).clamp(0.0, 1.0) : 1.0;
      if (opacity <= 0) continue;

      final dx = p.x * size.width + p.drift * size.width * localT;
      final dy = -20 + localT * (size.height + 40) * p.fallSpeed * 1.4;
      if (dy > size.height + 20) continue;

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(p.rotSpeed * localT * 2 * pi);
      paint.color = p.color.withOpacity(opacity);

      if (p.isStrip) {
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: p.size * 0.35, height: p.size * 1.8),
          paint,
        );
      } else {
        canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.65),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => true;
}