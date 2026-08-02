import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../core/constants/app_colors.dart';

/// Shows the gold coin rise as a full-screen overlay, then hands off to
/// Home right as the coin fades near the top of the screen.
///
/// MOTION BLUEPRINT (approved) -- six stages, all on a single straight
/// vertical (Y-axis only) path, coin always horizontally centered:
///   Stage 1 (0    -_t1 ms): coin appears, VERY slow rotation -- heavy,
///            elegant, luxury. No motion feels sudden.
///   Stage 2 (_t1  -_t2 ms): rise begins, rotation accelerates gradually.
///            Golden thruster boost ignites beneath the coin and rim
///            sparkles begin.
///   Stage 3 (_t2  -_t3 ms): coin reaches ~85% of screen height, rotation
///            a little faster but capped -- never blurs, never reads as a
///            casino spin. Thruster at full strength.
///   Stage 4 (_t3  -_t4 ms, ~200ms): PAUSE. Position freezes. Rotation
///            nearly stops (tiny residual wobble only). Metal reflections
///            keep sweeping across the rim. Thruster and dust fade to a
///            low ambient simmer, not fully off.
///   Stage 5 (_t4  -_t5 ms): diamond-style sparkle burst -- crossed glints
///            with a soft core, NOT confetti/fireworks/stars. Thruster
///            continues to fade out here.
///   Stage 6 (_t5  -_t6 ms): coin shrinks and fades as it "arrives" --
///            onNavigateHome() fires here so GoRouter swaps in Home right
///            as the coin vanishes, and Home's own header badge (real
///            backend-driven coinCount, see home_screen.dart) pops in to
///            complete the hand-off. This overlay never curves toward the
///            badge itself -- the hand-off is a screen transition, not a
///            diagonal flight, per the approved blueprint.
///
/// Everything below is a PURE FUNCTION of elapsed time in milliseconds --
/// no mutable particle lists, no per-frame spawn/despawn bookkeeping.
/// Every dust mote / rim flash / diamond glint is pre-seeded once (see the
/// _dust/_rimFlashes/_diamonds lists below) with its own spawn time and
/// lifespan, and the painter simply asks "is t inside this particle's
/// [spawn, spawn+life] window, and if so where is it and how bright" on
/// every frame. This keeps the whole animation deterministic and cheap to
/// repaint, and matches the style already used for the sparkle/burst
/// particles in the rest of this file.
///
/// KEY ARCHITECTURE POINT: the OverlayEntry is inserted into the app's
/// ROOT overlay (`rootOverlay: true`), independent of the Navigator/route
/// stack. The route change underneath (Confirm Recharge -> Home) does NOT
/// interrupt this overlay -- it keeps animating straight through, timed to
/// finish right as Home appears.
///
/// Usage (see emi_selection_screen.dart):
///   await showGoldCoinReward(
///     context,
///     plan.price,
///     onNavigateHome: () => context.go('/dashboard/home', extra: {...}),
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
      onNavigateHome: onNavigateHome,
      onDone: removeEntry,
    ),
  );

  Overlay.of(context, rootOverlay: true).insert(entry);
  return completer.future;
}

// ── Easing helpers (pure functions, 0..1 -> 0..1) ──
double _easeOutCubic(double x) => 1 - math.pow(1 - x, 3).toDouble();
double _easeInCubic(double x) => x * x * x;
double _easeInOutSine(double x) => -(math.cos(math.pi * x) - 1) / 2;
double _lerp(double a, double b, double t) => a + (b - a) * t;

class _GoldCoinRewardOverlay extends StatefulWidget {
  final VoidCallback onNavigateHome;
  final VoidCallback onDone;
  const _GoldCoinRewardOverlay({required this.onNavigateHome, required this.onDone});

  @override
  State<_GoldCoinRewardOverlay> createState() => _GoldCoinRewardOverlayState();
}

class _GoldCoinRewardOverlayState extends State<_GoldCoinRewardOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final _audioPlayer = AudioPlayer();

  // ── Stage boundaries, in milliseconds -- see class doc above ──
  static const double _t1 = 350;
  static const double _t2 = 1350;
  static const double _t3 = 1950;
  static const double _t4 = 2150;
  static const double _t5 = 2500;
  static const double _t6 = 2750;
  static const _totalDuration = Duration(milliseconds: 2750);

  bool _navigated = false;
  bool _closing = false;

  late final List<_DustMote> _dust;
  late final List<_RimFlash> _rimFlashes;
  late final List<_Diamond> _diamonds;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _totalDuration);
    _dust = _buildDust();
    _rimFlashes = _buildRimFlashes();
    _diamonds = _buildDiamonds();

    _controller.forward();
    _audioPlayer.play(AssetSource('sounds/recharge_success.mp3')).catchError((_) {});

    _controller.addListener(() {
      final t = _controller.value * _t6;
      // Fires once, right as the coin fades near the top -- Home takes
      // over from here (see class doc: this is a hand-off, not a flight
      // to a specific badge coordinate).
      if (!_navigated && t >= _t5) {
        _navigated = true;
        if (mounted) widget.onNavigateHome();
      }
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 100), _close);
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

  // ── Motion functions -- t is elapsed ms, all pure ──

  static double _rotationDegAt(double t) {
    if (t < _t1) return _lerp(0, 12, _easeOutCubic(t / _t1));
    if (t < _t2) return _lerp(12, 400, _easeInCubic((t - _t1) / (_t2 - _t1)));
    if (t < _t3) return _lerp(400, 760, _easeOutCubic((t - _t2) / (_t3 - _t2)));
    if (t < _t4) {
      final lt = (t - _t3) / (_t4 - _t3);
      return 760 + math.sin(lt * math.pi * 3) * 2.5; // tiny residual wobble, not a real spin
    }
    return _lerp(762, 900, _easeInOutSine((((t - _t4) / (_t6 - _t4)).clamp(0.0, 1.0))));
  }

  static double _posYAt(double t, double startY, double midY, double topY) {
    if (t < _t3) return _lerp(startY, midY, _easeOutCubic(t / _t3));
    if (t < _t4) return midY;
    return _lerp(midY, topY, _easeInCubic(((t - _t4) / (_t6 - _t4)).clamp(0.0, 1.0)));
  }

  static double _scaleAt(double t) {
    if (t < _t1) return _lerp(0.55, 1, _easeOutCubic(t / _t1));
    if (t < _t5) return 1;
    return _lerp(1, 0.4, _easeInCubic(((t - _t5) / (_t6 - _t5)).clamp(0.0, 1.0)));
  }

  static double _opacityAt(double t) {
    if (t < _t1) return (t / _t1).clamp(0.0, 1.0);
    if (t < _t5) return 1;
    return (1 - (t - _t5) / (_t6 - _t5)).clamp(0.0, 1.0);
  }

  /// 0..1 envelope used to modulate dust-mote/thruster brightness per
  /// stage -- NOT a spawn rate (all particles are pre-seeded, see above).
  static double _dustEnvelopeAt(double t) {
    if (t < _t1) return 0.3;
    if (t < _t2) return _lerp(0.4, 1.0, (t - _t1) / (_t2 - _t1));
    if (t < _t3) return 1.0;
    if (t < _t4) return 0.22; // pause -- low ambient simmer, not off
    if (t < _t5) return 0.4;
    return _lerp(0.4, 0, ((t - _t5) / (_t6 - _t5)).clamp(0.0, 1.0));
  }

  /// Same idea for the thruster boost beneath the coin.
  static double _thrusterEnvelopeAt(double t) {
    if (t < _t1) return _lerp(0, 1, _easeOutCubic(t / _t1));
    if (t < _t3) return 1;
    if (t < _t4) return _lerp(1, 0.2, (t - _t3) / (_t4 - _t3)); // pause -- fades to simmer
    if (t < _t5) return 0.15;
    return _lerp(0.15, 0, ((t - _t5) / (_t6 - _t5)).clamp(0.0, 1.0));
  }

  // ── Pre-seeded deterministic particles (built once in initState) ──

  List<_DustMote> _buildDust() {
    final rand = math.Random(7);
    return List.generate(90, (i) {
      final spawn = rand.nextDouble() * _t3; // emitted throughout stages 1-3, faded via envelope
      return _DustMote(
        spawnMs: spawn,
        lifeMs: 500 + rand.nextDouble() * 380,
        side: rand.nextBool() ? 1 : -1,
        baseYOffset: 6 + rand.nextDouble() * 16,
        xJitter: rand.nextDouble() * 10,
        drift: (rand.nextDouble() * 0.5 - 0.25),
        rise: 26 + rand.nextDouble() * 30,
        size: 1.0 + rand.nextDouble() * 1.6,
        warm: rand.nextDouble() < 0.7,
      );
    });
  }

  List<_RimFlash> _buildRimFlashes() {
    final rand = math.Random(11);
    // Roughly one flash every ~180ms through the active rotation window --
    // tiny rim sparkles catching the light as the coin turns.
    final events = <_RimFlash>[];
    var t = 120.0;
    while (t < _t4) {
      final angleDeg = _rotationDegAt(t);
      events.add(_RimFlash(
        spawnMs: t,
        lifeMs: 260 + rand.nextDouble() * 120,
        angleRad: angleDeg * math.pi / 180,
        size: 1.0 + rand.nextDouble() * 0.8,
      ));
      t += 80 + rand.nextDouble() * 40;
    }
    return events;
  }

  List<_Diamond> _buildDiamonds() {
    final rand = math.Random(19);
    return List.generate(14, (i) {
      final angle = rand.nextDouble() * 2 * math.pi;
      final dist = 8 + rand.nextDouble() * 16;
      return _Diamond(
        dx: math.cos(angle) * dist,
        dy: math.sin(angle) * dist,
        size: 3 + rand.nextDouble() * 2.5,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final centerX = size.width / 2;
    final startY = size.height * 0.9;
    final midY = size.height * 0.15;
    final topY = size.height * 0.08;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * _t6;
        final y = _posYAt(t, startY, midY, topY);
        final rotationDeg = _rotationDegAt(t);
        final scale = _scaleAt(t);
        final opacity = _opacityAt(t);
        final squish = math.cos(rotationDeg * math.pi / 180);

        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _CoinFxPainter(
                    t: t,
                    centerX: centerX,
                    coinY: y,
                    coinScale: scale,
                    coinOpacity: opacity,
                    rotationDeg: rotationDeg,
                    dust: _dust,
                    posYAt: (tt) => _posYAt(tt, startY, midY, topY),
                    dustEnvelopeAt: _dustEnvelopeAt,
                    thrusterEnvelopeAt: _thrusterEnvelopeAt,
                    rimFlashes: _rimFlashes,
                    diamonds: _diamonds,
                    pauseStart: _t3,
                    pauseEnd: _t4,
                    burstStart: _t4,
                  ),
                ),
              ),
            ),
            _buildCoin(centerX, y, scale, opacity, rotationDeg, squish),
          ],
        );
      },
    );
  }

  Widget _buildCoin(double cx, double y, double scale, double opacity, double rotationDeg, double squish) {
    const coinSize = 84.0;
    return Positioned(
      left: cx - (coinSize * scale) / 2,
      top: y - (coinSize * scale) / 2,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0022)
              ..scale(scale)
              ..rotateY(rotationDeg * math.pi / 180),
            child: Image.asset(
              'assets/images/youpi_coin.png',
              width: coinSize,
              height: coinSize,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                width: coinSize,
                height: coinSize,
                decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle),
                child: const Icon(Icons.monetization_on_rounded, color: Colors.black, size: 44),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Particle models -- all fields are fixed at construction (seeded),
// nothing here is ever mutated after creation ──

class _DustMote {
  final double spawnMs;
  final double lifeMs;
  final int side;
  final double baseYOffset;
  final double xJitter;
  final double drift;
  final double rise;
  final double size;
  final bool warm;
  _DustMote({
    required this.spawnMs,
    required this.lifeMs,
    required this.side,
    required this.baseYOffset,
    required this.xJitter,
    required this.drift,
    required this.rise,
    required this.size,
    required this.warm,
  });
}

class _RimFlash {
  final double spawnMs;
  final double lifeMs;
  final double angleRad;
  final double size;
  _RimFlash({required this.spawnMs, required this.lifeMs, required this.angleRad, required this.size});
}

class _Diamond {
  final double dx;
  final double dy;
  final double size;
  _Diamond({required this.dx, required this.dy, required this.size});
}

/// Draws everything EXCEPT the coin itself: the golden thruster boost
/// beneath the coin, the drifting dust trail, the rim light-flashes, and
/// the diamond sparkle burst. All pure functions of `t` -- see class doc
/// on _GoldCoinRewardOverlayState for why nothing here is mutable state.
class _CoinFxPainter extends CustomPainter {
  final double t;
  final double centerX;
  final double coinY;
  final double coinScale;
  final double coinOpacity;
  final double rotationDeg;
  final List<_DustMote> dust;
  final double Function(double) posYAt;
  final double Function(double) dustEnvelopeAt;
  final double Function(double) thrusterEnvelopeAt;
  final List<_RimFlash> rimFlashes;
  final List<_Diamond> diamonds;
  final double pauseStart;
  final double pauseEnd;
  final double burstStart;

  _CoinFxPainter({
    required this.t,
    required this.centerX,
    required this.coinY,
    required this.coinScale,
    required this.coinOpacity,
    required this.rotationDeg,
    required this.dust,
    required this.posYAt,
    required this.dustEnvelopeAt,
    required this.thrusterEnvelopeAt,
    required this.rimFlashes,
    required this.diamonds,
    required this.pauseStart,
    required this.pauseEnd,
    required this.burstStart,
  });

  static const double _coinRadius = 42;

  @override
  void paint(Canvas canvas, Size size) {
    final rotRad = rotationDeg * math.pi / 180;
    final squish = math.cos(rotRad).abs();
    final w = _coinRadius * 2 * math.max(squish, 0.08) * coinScale;
    final h = _coinRadius * 2 * coinScale;

    _paintThruster(canvas, w);
    _paintDust(canvas);
    _paintRimGlow(canvas, w, h, rotRad);
    _paintRimFlashes(canvas);
    _paintDiamonds(canvas);
  }

  // Warm volumetric glow + a concentrated core beam + a few softly flowing
  // streaks -- deliberately restrained (no rainbow colors, no confetti
  // shower) so it reads as premium propulsion, not a game power-up.
  void _paintThruster(Canvas canvas, double coinWidth) {
    final intensity = thrusterEnvelopeAt(t);
    if (intensity <= 0.01) return;
    final baseY = coinY + (_coinRadius * 2 * coinScale) * 0.28;
    final beamLength = 58 + coinWidth * 0.3;

    final glowH = beamLength * 0.9;
    final glowCenter = Offset(centerX, baseY + glowH * 0.32);
    final glowPaint = Paint()
      ..shader = RadialGradient(colors: [
        AppColors.secondary.withOpacity(0.4 * intensity),
        AppColors.secondary.withOpacity(0),
      ]).createShader(Rect.fromCircle(center: glowCenter, radius: glowH * 0.72));
    canvas.drawCircle(glowCenter, glowH * 0.72, glowPaint);

    final pulse = 0.75 + 0.25 * math.sin(t * 0.02);
    final coreLen = 34 + coinWidth * 0.18;
    final coreRect = Rect.fromLTWH(centerX - 2.2, baseY, 4.4, coreLen);
    final corePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withOpacity(0.75 * intensity * pulse),
          Colors.white.withOpacity(0),
        ],
      ).createShader(coreRect);
    canvas.drawRRect(RRect.fromRectAndRadius(coreRect, const Radius.circular(2)), corePaint);

    for (var s = 0; s < 4; s++) {
      final baseOffset = (s - 1.5) * 6.0;
      final phase = s * 1.7;
      final warm = s.isEven;
      final color = warm ? const Color(0xFFFFD278) : const Color(0xFFFFF4D6);
      for (double yy = 0; yy < beamLength; yy += 5) {
        final frac = yy / beamLength;
        final x = centerX +
            baseOffset * (1 - frac * 0.3) +
            math.sin(yy * 0.09 + phase + t * 0.006) * (5.5 * (1 - frac * 0.4));
        final yPos = baseY + 6 + yy;
        final a = (1 - frac) * 0.6 * intensity;
        if (a < 0.02) continue;
        final r = (1 - frac) * 1.8 * intensity + 0.3;
        canvas.drawCircle(Offset(x, yPos), r, Paint()..color = color.withOpacity(a));
      }
    }
  }

  void _paintDust(Canvas canvas) {
    for (final d in dust) {
      final localT = (t - d.spawnMs) / d.lifeMs;
      if (localT < 0 || localT > 1) continue;
      final envelope = dustEnvelopeAt(d.spawnMs);
      if (envelope <= 0.02) continue;
      final coinYAtSpawn = posYAt(d.spawnMs);
      final x = centerX + d.side * (18 + d.xJitter) + d.drift * localT * 14;
      final y = coinYAtSpawn + d.baseYOffset - d.rise * localT;
      final alpha = (1 - localT) * envelope * 0.95;
      if (alpha <= 0.02) continue;
      final color = d.warm ? const Color(0xFFFFD778) : const Color(0xFFFFF6DE);
      canvas.drawCircle(Offset(x, y), d.size, Paint()..color = color.withOpacity(alpha));
    }
  }

  // Continuous specular sweep -- a handful of points around the coin's
  // current (rotation-squished) rim, brightened only where they currently
  // face an implied light source. This is what makes the metal look like
  // it's genuinely reflecting light as it turns, including during the
  // Stage 4 pause when rotation itself has nearly stopped but the sheen
  // should still visibly move.
  void _paintRimGlow(Canvas canvas, double w, double h, double rotRad) {
    const lightAngle = -math.pi * 0.35;
    double sweepAngle;
    if (t >= pauseStart && t < pauseEnd) {
      final lt = (t - pauseStart) / (pauseEnd - pauseStart);
      sweepAngle = lt * math.pi * 2; // reflections keep moving even though the coin itself barely rotates
    } else {
      sweepAngle = rotRad;
    }
    for (var i = 0; i < 6; i++) {
      final ang = (i / 6) * 2 * math.pi + sweepAngle;
      final px = centerX + math.cos(ang) * (w / 2);
      final py = coinY + math.sin(ang) * (h / 2) * 0.9;
      final spec = math.max(0.0, math.cos(ang - lightAngle));
      final a = math.pow(spec, 4).toDouble() * coinOpacity * 0.85;
      if (a < 0.05) continue;
      canvas.drawCircle(Offset(px, py), 1.4, Paint()..color = Colors.white.withOpacity(a));
    }
  }

  void _paintRimFlashes(Canvas canvas) {
    for (final f in rimFlashes) {
      final localT = (t - f.spawnMs) / f.lifeMs;
      if (localT < 0 || localT > 1) continue;
      final r = _coinRadius * coinScale;
      final x = centerX + math.cos(f.angleRad) * r * 0.4;
      final y = coinY + math.sin(f.angleRad) * r * 0.35;
      final alpha = (1 - localT) * 0.8;
      canvas.drawCircle(Offset(x, y), f.size, Paint()..color = Colors.white.withOpacity(alpha));
    }
  }

  // Diamond-style burst at the end of the pause -- crossed glints with a
  // soft core, deliberately NOT circular confetti and NOT star shapes.
  void _paintDiamonds(Canvas canvas) {
    final localT = (t - burstStart) / 420;
    if (localT < 0 || localT > 1) return;
    final travel = _easeOutCubic(localT.clamp(0.0, 1.0));
    final alpha = (1 - localT).clamp(0.0, 1.0);
    for (final dm in diamonds) {
      final x = centerX + dm.dx * travel;
      final y = coinY + dm.dy * travel;
      _drawDiamondGlint(canvas, Offset(x, y), dm.size, alpha);
    }
  }

  void _drawDiamondGlint(Canvas canvas, Offset center, double size, double alpha) {
    final linePaint = Paint()
      ..color = Colors.white.withOpacity(alpha)
      ..strokeWidth = 1;
    canvas.drawLine(center - Offset(size, 0), center + Offset(size, 0), linePaint);
    canvas.drawLine(center - Offset(0, size), center + Offset(0, size), linePaint);
    final glowPaint = Paint()
      ..shader = RadialGradient(colors: [
        Colors.white.withOpacity(alpha),
        Colors.white.withOpacity(0),
      ]).createShader(Rect.fromCircle(center: center, radius: size * 0.7));
    canvas.drawCircle(center, size * 0.7, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _CoinFxPainter oldDelegate) => oldDelegate.t != t;
}