import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/widgets/youpi_card.dart';
import '../invest/invest_viewmodel.dart';
import '../../data/models/goal_model.dart';
import 'goals_viewmodel.dart';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});
  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  bool _showActive = true;

  @override
  void initState() {
    super.initState();
    // Need a live gold price to convert ₹ saved into grams below --
    // reuses the same InvestViewModel the rest of the invest flow uses.
    WidgetsBinding.instance.addPostFrameCallback((_) =>
        context.read<InvestViewModel>().loadGold());
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<GoalsViewModel, InvestViewModel>(builder: (ctx, goalsVm, investVm, _) {
      final goals = _showActive ? goalsVm.activeGoals : goalsVm.completedGoals;
      final totalSaved = goalsVm.totalSaved;
      final grams = investVm.gold.pricePerGram > 0 ? totalSaved / investVm.gold.pricePerGram : 0.0;

      // Same "derive from today's live price move" approach used on the
      // hub/portfolio screens -- there's no cost-basis field to compute a
      // true lifetime gain from.
      final gainPercent = investVm.gold.priceChange;
      final gainAmount = totalSaved * (gainPercent.abs() / (100 + gainPercent.abs()));
      final isUp = investVm.gold.isPriceUp;

      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(title: const Text('My goals'), backgroundColor: AppColors.backgroundPrimary),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.paddingPage),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // ── Total saved card ──────────────────────────────────
            GlassCard(
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Total saved in gold', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 4),
                    Text(CurrencyFormatter.format(totalSaved), style: AppTextStyles.amountLarge),
                    const SizedBox(height: 8),
                    Row(children: [
                      Icon(Icons.trending_up_rounded, size: 14, color: isUp ? AppColors.success : AppColors.error),
                      const SizedBox(width: 4),
                      Text(
                        '${grams.toStringAsFixed(2)} g · ${isUp ? '+' : '-'}${CurrencyFormatter.format(gainAmount)} gain',
                        style: AppTextStyles.bodySmall.copyWith(color: isUp ? AppColors.success : AppColors.error),
                      ),
                    ]),
                  ]),
                ),
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: const Text('🪙', style: TextStyle(fontSize: 20)),
                ),
              ]),
            ),

            const SizedBox(height: 20),
            // ── Active/Completed toggle ───────────────────────────
            Row(children: [
              GestureDetector(
                onTap: () => setState(() => _showActive = true),
                child: _FilterChip(label: 'Active · ${goalsVm.activeGoals.length}', selected: _showActive),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => setState(() => _showActive = false),
                child: _FilterChip(label: 'Completed · ${goalsVm.completedGoals.length}', selected: !_showActive),
              ),
            ]),

            const SizedBox(height: 16),
            if (goals.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    _showActive ? 'No active goals yet' : 'No completed goals yet',
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
                  ),
                ),
              )
            else
              for (int i = 0; i < goals.length; i++) ...[
                GestureDetector(
                  onTap: () => ctx.push('/invest/goals/${goals[i].id}'),
                  child: _GoalRow(goal: goals[i], ringColor: goalRingColor(goals[i].category)),
                ),
                const SizedBox(height: 10),
              ],

            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => ctx.push('/invest/goals/create'),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.textSecondary.withOpacity(0.3), width: 1.2),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.add_rounded, color: AppColors.textPrimary, size: 18),
                  const SizedBox(width: 8),
                  Text('Create a goal', style: AppTextStyles.labelLarge),
                ]),
              ),
            ),
          ]),
        ),
      );
    });
  }
}

// Deterministic color per category so a goal's ring looks the same on the
// list and its detail screen, instead of an index that shifts as goals
// are added/removed/filtered.
Color goalRingColor(String category) {
  switch (category) {
    case 'Birthday': return Colors.blue;
    case 'Vehicle': return Colors.blue;
    case 'Travel': return Colors.purpleAccent;
    case 'Education': return AppColors.primary;
    default: return AppColors.secondary;
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  const _FilterChip({required this.label, required this.selected});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? Colors.white : AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(label, style: AppTextStyles.bodyMedium.copyWith(
          color: selected ? Colors.black : AppColors.textSecondary, fontWeight: FontWeight.w600)),
    );
  }
}

class _GoalRow extends StatelessWidget {
  final GoalModel goal;
  final Color ringColor;
  const _GoalRow({required this.goal, required this.ringColor});

  @override
  Widget build(BuildContext context) {
    return YoupiCard(
      child: Row(children: [
        _ProgressRing(progress: goal.progress, color: ringColor),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(goal.title, style: AppTextStyles.labelLarge),
            const SizedBox(height: 2),
            Text(
              '${CurrencyFormatter.format(goal.savedAmount)} of ${CurrencyFormatter.format(goal.targetAmount)}',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              goal.completed
                  ? 'Completed'
                  : (goal.isOnTrack
                      ? 'On track · ${goal.monthsLeft} months left'
                      : 'Behind by ${CurrencyFormatter.format(goal.behindAmount)}'),
              style: AppTextStyles.bodySmall.copyWith(
                color: goal.completed || goal.isOnTrack ? AppColors.success : AppColors.secondary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ]),
        ),
        const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
      ]),
    );
  }
}

class ProgressRing extends StatelessWidget {
  final double progress;
  final Color color;
  final double size;
  const ProgressRing({super.key, required this.progress, required this.color, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size, height: size,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(size: Size(size, size), painter: RingPainter(progress: progress, color: color)),
      ]),
    );
  }
}

class _ProgressRing extends StatelessWidget {
  final double progress;
  final Color color;
  const _ProgressRing({required this.progress, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56, height: 56,
      child: Stack(alignment: Alignment.center, children: [
        CustomPaint(size: const Size(56, 56), painter: RingPainter(progress: progress, color: color)),
        Text('${(progress * 100).round()}%', style: AppTextStyles.bodySmall.copyWith(fontWeight: FontWeight.bold)),
      ]),
    );
  }
}

class RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 4;
    final trackPaint = Paint()
      ..color = AppColors.divider
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, trackPaint);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

// Same hand-built green glass card used on the hub/portfolio screens --
// YoupiGlassCard's border/glow wasn't rendering on device.
class GlassCard extends StatelessWidget {
  final Widget child;
  const GlassCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppColors.backgroundPrimary,
        border: Border.all(color: AppColors.primary.withOpacity(0.28)),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.primary.withOpacity(0.07), AppColors.backgroundPrimary],
        ),
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.12), blurRadius: 24, spreadRadius: -14)],
      ),
      child: child,
    );
  }
}