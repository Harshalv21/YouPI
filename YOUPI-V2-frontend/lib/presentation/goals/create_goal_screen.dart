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

class CreateGoalScreen extends StatefulWidget {
  const CreateGoalScreen({super.key});
  @override
  State<CreateGoalScreen> createState() => _CreateGoalScreenState();
}

class _CreateGoalScreenState extends State<CreateGoalScreen> {
  static const _categories = [
    {'label': 'Birthday', 'emoji': '🎂'},
    {'label': 'Vehicle', 'emoji': '🚗'},
    {'label': 'Travel', 'emoji': '✈️'},
    {'label': 'Education', 'emoji': '🎓'},
    {'label': 'Other', 'emoji': '🏷️'},
  ];

  int _selectedCategory = 0;
  final _nameController = TextEditingController(text: 'Birthday party');
  final _amountController = TextEditingController(text: '50000');
  DateTime _achieveBy = DateTime.now().add(const Duration(days: 180));
  SavingFrequency _frequency = SavingFrequency.monthly;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) =>
        context.read<InvestViewModel>().loadGold());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  // Number of installments between now and the target date, at the chosen
  // frequency -- always at least 1 so amount-per-installment never divides
  // by zero.
  int get _installments {
    final days = _achieveBy.difference(DateTime.now()).inDays;
    switch (_frequency) {
      case SavingFrequency.daily:
        return days < 1 ? 1 : days;
      case SavingFrequency.weekly:
        return (days / 7).ceil().clamp(1, 999999);
      case SavingFrequency.monthly:
        final now = DateTime.now();
        final months = (_achieveBy.year - now.year) * 12 + (_achieveBy.month - now.month);
        return months < 1 ? 1 : months;
    }
  }

  String get _durationLabel {
    final n = _installments;
    switch (_frequency) {
      case SavingFrequency.daily:
        return '$n day${n == 1 ? '' : 's'}';
      case SavingFrequency.weekly:
        return '$n week${n == 1 ? '' : 's'}';
      case SavingFrequency.monthly:
        return '$n month${n == 1 ? '' : 's'}';
    }
  }

  String get _deductLabel {
    switch (_frequency) {
      case SavingFrequency.daily:
        return 'Every day';
      case SavingFrequency.weekly:
        const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
        return 'Every ${weekdays[DateTime.now().weekday - 1]}';
      case SavingFrequency.monthly:
        return '${_ordinal(DateTime.now().day)} of every month';
    }
  }

  String _ordinal(int n) {
    if (n >= 11 && n <= 13) return '${n}th';
    switch (n % 10) {
      case 1: return '${n}st';
      case 2: return '${n}nd';
      case 3: return '${n}rd';
      default: return '${n}th';
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = double.tryParse(_amountController.text) ?? 0;
    final perInstallment = target > 0 ? (target / _installments).ceilToDouble() : 0.0;

    return Consumer<InvestViewModel>(builder: (ctx, investVm, _) {
      // "Gold at today's rate" is illustrative -- how much 24K gold the
      // full target converts to at the live price right now, not a
      // commitment (the actual rate on each deduction day will differ).
      final goldGrams = investVm.gold.pricePerGram > 0 ? target / investVm.gold.pricePerGram : 0.0;

      return Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        appBar: AppBar(title: const Text('Create a goal'), backgroundColor: AppColors.backgroundPrimary),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(AppDimensions.paddingPage),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Choose a category', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: List.generate(_categories.length, (i) {
                final selected = _selectedCategory == i;
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.primary.withOpacity(0.18) : AppColors.backgroundCard,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: selected ? AppColors.primary : Colors.transparent),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_categories[i]['emoji']!, style: const TextStyle(fontSize: 15)),
                      const SizedBox(width: 6),
                      Text(_categories[i]['label']!,
                          style: AppTextStyles.bodyMedium.copyWith(
                              color: selected ? AppColors.primary : AppColors.textSecondary,
                              fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
                    ]),
                  ),
                );
              }),
            ),

            const SizedBox(height: 22),
            Text('Goal name', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              style: AppTextStyles.labelLarge,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.backgroundCard,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),

            const SizedBox(height: 20),
            Text('Target amount', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              style: AppTextStyles.labelLarge,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.backgroundCard,
                prefixText: '₹',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),

            const SizedBox(height: 20),
            Text('Achieve by', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _achieveBy,
                  firstDate: DateTime.now().add(const Duration(days: 7)),
                  lastDate: DateTime.now().add(const Duration(days: 365 * 10)),
                );
                if (picked != null) setState(() => _achieveBy = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(color: AppColors.backgroundCard, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  '${_achieveBy.day} ${_monthName(_achieveBy.month)} ${_achieveBy.year}',
                  style: AppTextStyles.labelLarge,
                ),
              ),
            ),

            const SizedBox(height: 20),
            Text('Saving frequency', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: AppColors.backgroundCard, borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                for (final f in SavingFrequency.values)
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _frequency = f),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _frequency == f ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          f == SavingFrequency.daily ? 'Daily' : f == SavingFrequency.weekly ? 'Weekly' : 'Monthly',
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: _frequency == f ? Colors.black : AppColors.textSecondary,
                            fontWeight: _frequency == f ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),

            const SizedBox(height: 20),
            YoupiCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('YOUR PLAN', style: AppTextStyles.captionText.copyWith(color: AppColors.textSecondary, letterSpacing: 1)),
                const SizedBox(height: 6),
                Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text(CurrencyFormatter.format(perInstallment), style: AppTextStyles.amountMedium),
                  const SizedBox(width: 6),
                  Text('per ${_frequency == SavingFrequency.daily ? 'day' : _frequency == SavingFrequency.weekly ? 'week' : 'month'}',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                ]),
                const SizedBox(height: 14),
                const Divider(color: AppColors.divider, height: 1),
                const SizedBox(height: 14),
                _PlanRow('Duration', _durationLabel),
                const SizedBox(height: 10),
                _PlanRow('Gold at today\'s rate', '${goldGrams.toStringAsFixed(2)} g'),
                const SizedBox(height: 10),
                _PlanRow('Deduct on', _deductLabel),
                const SizedBox(height: 10),
                const _PlanRow('Pay from', 'YouPI wallet'),
              ]),
            ),

            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.secondary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.info_outline_rounded, color: AppColors.secondary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your savings are stored as 24K digital gold in an insured vault by Augmont.',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.secondary),
                  ),
                ),
              ]),
            ),

            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: (target <= 0 || _nameController.text.trim().isEmpty) ? null : () {
                  context.read<GoalsViewModel>().addGoal(
                    title: _nameController.text.trim(),
                    category: _categories[_selectedCategory]['label']!,
                    categoryEmoji: _categories[_selectedCategory]['emoji']!,
                    targetAmount: target,
                    deadline: _achieveBy,
                    frequency: _frequency,
                    installmentAmount: perInstallment,
                  );
                  // Pop back to My Goals -- it's the same GoalsViewModel
                  // instance, so the list picks up the new goal instantly.
                  ctx.pop();
                },
                child: Text('Start saving',
                    style: AppTextStyles.labelLarge.copyWith(color: Colors.black, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      );
    });
  }

  String _monthName(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ][m - 1];
}

class _PlanRow extends StatelessWidget {
  final String label;
  final String value;
  const _PlanRow(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
      Text(value, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
    ]);
  }
}