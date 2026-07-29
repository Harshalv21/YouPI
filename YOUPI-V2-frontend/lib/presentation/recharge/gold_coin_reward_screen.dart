import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_text_styles.dart';

/// Shows the coin-toss reward as a semi-transparent OVERLAY on top of the
/// current screen (e.g. the payment/confirm screen), not a separate
/// full-screen route. Awaiting this returns once the animation finishes
/// (or the user taps to skip) -- caller is then responsible for navigating
/// to home, keeping all navigation decisions in one place rather than
/// split between this widget and the router.
///
/// Usage (see emi_selection_screen.dart):
///   await showGoldCoinReward(context, plan.price);
///   if (context.mounted) context.go('/dashboard/home');
Future<void> showGoldCoinReward(BuildContext context, double rechargeAmount) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'Gold coin reward',
    // Medium-transparent -- the screen underneath (Payment Options, per
    // the reference screenshot) stays visible/dimmed through this, rather
    // than being replaced by a solid black page.
    barrierColor: Colors.black.withOpacity(0.55),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, __) => _GoldCoinRewardOverlay(rechargeAmount: rechargeAmount),
    transitionBuilder: (ctx, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}

class _GoldCoinRewardOverlay extends StatefulWidget {
  final double rechargeAmount;
  const _GoldCoinRewardOverlay({required this.rechargeAmount});

  @override
  State<_GoldCoinRewardOverlay> createState() => _GoldCoinRewardOverlayState();
}

class _GoldCoinRewardOverlayState extends State<_GoldCoinRewardOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Sparkle> _sparkles;

  static const _totalDuration = Duration(milliseconds: 2600);
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _totalDuration);
    _sparkles = List.generate(26, (i) => _Sparkle(i));

    _controller.forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 500), _close);
      }
    });
  }

  void _close() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _valueEarned => widget.rechargeAmount * 0.01;

  @override
  Widget build(BuildContext context) {
    // NOTE: no Scaffold, no opaque background fill -- this sits on top of
    // whatever screen triggered it (dimmed by barrierColor above), which
    // is the whole point of using it as an overlay rather than a route.
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        // Lets an impatient user skip straight past -- never trap someone
        // in a forced animation on a real-money screen.
        onTap: _close,
        child: SizedBox.expand(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              return Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _SparklePainter(
                        sparkles: _sparkles,
                        t: t,
                        coinCenter: _coinPosition(context, t),
                      ),
                    ),
                  ),
                  _buildCoin(t),
                  _buildText(t),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  /// Coin's on-screen position over time -- tosses up from bottom-center,
  /// overshoots slightly past its resting point, then settles with a
  /// small idle bob. Resting point is mid-screen-ish so it reads well
  /// whether it's overlaying a tall or short screen behind it.
  Offset _coinPosition(BuildContext context, double t) {
    final size = MediaQuery.of(context).size;
    final startY = size.height * 0.85;
    final restY = size.height * 0.40;
    final overshootY = restY - 40;

    double y;
    if (t < 0.55) {
      final localT = t / 0.55;
      final eased = 1 - math.pow(1 - localT, 3).toDouble();
      y = startY + (overshootY - startY) * eased;
    } else if (t < 0.75) {
      final localT = (t - 0.55) / 0.20;
      final eased = Curves.easeOutBack.transform(localT);
      y = overshootY + (restY - overshootY) * eased;
    } else {
      final idleT = (t - 0.75) / 0.25;
      y = restY + math.sin(idleT * math.pi * 3) * 4;
    }
    return Offset(size.width / 2, y);
  }

  Widget _buildCoin(double t) {
    final spins = t < 0.75 ? t * 6 * math.pi : 6 * math.pi + math.sin((t - 0.75) / 0.25 * math.pi * 3) * 0.15;
    final scale = t < 0.12 ? (t / 0.12).clamp(0.0, 1.0) : 1.0;
    final coinPos = _coinPosition(context, t);

    return Positioned(
      left: coinPos.dx - 55,
      top: coinPos.dy - 55,
      child: Transform.scale(
        scale: scale,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.003)
            ..rotateY(spins),
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
    );
  }

  Widget _buildText(double t) {
    if (t < 0.65) return const SizedBox.shrink();
    final localT = ((t - 0.65) / 0.35).clamp(0.0, 1.0);
    final size = MediaQuery.of(context).size;

    return Positioned(
      top: size.height * 0.40 + 90,
      left: 0,
      right: 0,
      child: Opacity(
        opacity: localT,
        child: Transform.translate(
          offset: Offset(0, (1 - localT) * 12),
          child: Column(
            children: [
              // Shadow-backed text since this sits over a dimmed but still
              // visible underlying screen, not a flat black background --
              // needs to stay readable over whatever content is behind it.
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