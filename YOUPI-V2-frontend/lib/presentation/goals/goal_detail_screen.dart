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
import 'goals_screen.dart' show GlassCard, ProgressRing, goalRingColor;
import 'goals_viewmodel.dart';

class GoalDetailScreen extends StatefulWidget {
  final String goalId;
  const GoalDetailScreen({super.key, required this.goalId});

  @override
  State<GoalDetailScreen> createState() => _GoalDetailScreenState();
}

class _GoalDetailScreenState extends State<GoalDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) =>
        context.read<InvestViewModel>().loadGold());
  }

  Future<void> _showAddMoneyDialog(BuildContext context, GoalsViewModel goalsVm, double pricePerGram) async {
    final controller = TextEditingController();
    final amount = await showDialog<double>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppColors.backgroundCard,
        title: Text('Add money', style: AppTextStyles.labelLarge),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: AppTextStyles.amountMedium,
          decoration: const InputDecoration(prefixText: '₹', hintText: 'e.g. 2000'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, double.tryParse(controller.text)),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (amount != null && amount > 0) {
      goalsVm.addContribution(widget.goalId, amount, pricePerGram);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<GoalsViewModel, InvestViewModel>(builder: (ctx, goalsVm, investVm, _) {
      final goal = goalsVm.goalById(widget.goalId);
      if (goal == null) {
        // Goal was deleted (e.g. from this same screen's menu) while this
        // route was still on the stack -- bail out instead of crashing on
        // a null goal.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (ctx.mounted) ctx.pop();
        });
        return const Scaffold(backgroundColor: AppColors.backgroundPrimary, body: SizedBox.shrink());
      }

      final ringColor = goalRingColor(goal.category);
      final currentValue = goal.totalGramsHeld * investVm.gold.pricePerGram;
      final gain = currentValue - goal.totalInvested;
      final isGainPositive = gain >= 0;

      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(
          title: Text(goal.title),
          backgroundColor: AppColors.backgroundPrimary,
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded),
              color: AppColors.backgroundCard,
              onSelected: (value) {
                if (value == 'toggle') {
                  goalsVm.toggleAutoDebit(goal.id);
                } else if (value == 'delete') {
                  goalsVm.deleteGoal(goal.id);
                  ctx.pop();
                }
              },
              itemBuilder: (menuCtx) => [
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(goal.autoDebitActive ? 'Pause auto-debit' : 'Resume auto-debit'),
                ),
                const PopupMenuItem(value: 'delete', child: Text('Delete goal')),
              ],
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.paddingPage),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // ── Big progress ring ──────────────────────────────────
            Center(
              child: Stack(alignment: Alignment.center, children: [
                ProgressRing(progress: goal.progress, color: ringColor, size: 220),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('saved so far', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 4),
                  Text(CurrencyFormatter.format(goal.savedAmount), style: AppTextStyles.amountLarge),
                  const SizedBox(height: 4),
                  Text('of ${CurrencyFormatter.format(goal.targetAmount)}',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                ]),
              ]),
            ),
            const SizedBox(height: 14),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: (goal.completed || goal.isOnTrack ? AppColors.success : AppColors.secondary).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  goal.completed ? 'Completed' : (goal.isOnTrack ? 'On track' : 'Behind by ${CurrencyFormatter.format(goal.behindAmount)}'),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: goal.completed || goal.isOnTrack ? AppColors.success : AppColors.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: YoupiCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Gold held', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    Text('${goal.totalGramsHeld.toStringAsFixed(2)} g', style: AppTextStyles.labelLarge),
                    const SizedBox(height: 4),
                    Text(
                      '${isGainPositive ? '+' : '-'}${CurrencyFormatter.format(gain.abs())} gain',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: isGainPositive ? AppColors.success : AppColors.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: YoupiCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Time left', style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                    const SizedBox(height: 6),
                    Text('${goal.daysLeft} days', style: AppTextStyles.labelLarge),
                    const SizedBox(height: 4),
                    Text(_formatDate(goal.deadline), style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                  ]),
                ),
              ),
            ]),

            const SizedBox(height: 20),
            YoupiCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Auto-debit', style: AppTextStyles.labelLarge),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (goal.autoDebitActive ? AppColors.success : AppColors.textSecondary).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      goal.autoDebitActive ? 'Active' : 'Paused',
                      style: AppTextStyles.captionText.copyWith(
                        color: goal.autoDebitActive ? AppColors.success : AppColors.textSecondary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                _Row(_frequencyLabel(goal.frequency), CurrencyFormatter.format(goal.installmentAmount)),
                const SizedBox(height: 10),
                _Row('Next deduction', _formatDate(goal.nextDeductionDate)),
                const SizedBox(height: 10),
                // NOTE: no linked-payment-method field exists anywhere in
                // the app yet -- static label until a real "funding source"
                // API exists to read this from (same situation as the
                // "Credited to" row on digital_gold_screen.dart).
                const _Row('Pay from', 'Wallet · UPI fallback'),
              ]),
            ),

            const SizedBox(height: 24),
            Text('Recent contributions', style: AppTextStyles.headlineSmall),
            const SizedBox(height: 12),
            if (goal.contributions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('No contributions yet', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
              )
            else
              for (int i = 0; i < goal.contributions.length; i++) ...[
                _ContributionRow(contribution: goal.contributions[i]),
                if (i != goal.contributions.length - 1)
                  const Divider(color: AppColors.divider, height: 22),
              ],

            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppColors.textSecondary.withOpacity(0.3)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    // No withdraw-from-goal endpoint exists yet (would need
                    // to reverse gold back to wallet balance) -- surfaced
                    // honestly instead of faking a transaction.
                    onPressed: () => ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Withdraw is coming soon')),
                    ),
                    child: Text('Withdraw', style: AppTextStyles.labelLarge.copyWith(fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () => _showAddMoneyDialog(ctx, goalsVm, investVm.gold.pricePerGram),
                    child: Text('Add money', style: AppTextStyles.labelLarge.copyWith(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      );
    });
  }

  String _frequencyLabel(SavingFrequency f) {
    switch (f) {
      case SavingFrequency.daily: return 'Daily amount';
      case SavingFrequency.weekly: return 'Weekly amount';
      case SavingFrequency.monthly: return 'Monthly amount';
    }
  }

  String _formatDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
      Text(value, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
    ]);
  }
}

class _ContributionRow extends StatelessWidget {
  final GoalContribution contribution;
  const _ContributionRow({required this.contribution});

  @override
  Widget build(BuildContext context) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = contribution.date;
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(contribution.type, style: AppTextStyles.labelLarge),
          const SizedBox(height: 2),
          Text(
            '${d.day} ${months[d.month - 1]} · ${contribution.grams.toStringAsFixed(2)} g @ ${CurrencyFormatter.format(contribution.pricePerGram)}/g',
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
          ),
        ]),
      ),
      Text(CurrencyFormatter.format(contribution.amount), style: AppTextStyles.labelLarge),
    ]);
  }
}