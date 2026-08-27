// No goals endpoint exists anywhere in invest_repository.dart yet -- this
// model backs an in-memory-only GoalsViewModel until a real goals API
// exists to persist these to.

enum SavingFrequency { daily, weekly, monthly }

// Each contribution records the actual grams bought and the price paid per
// gram at that moment -- this is what lets the detail screen show a real
// gain (current value vs. what was actually paid) instead of a proxy.
class GoalContribution {
  final String type; // 'Auto-debit' | 'Manual top-up'
  final DateTime date;
  final double grams;
  final double pricePerGram;

  const GoalContribution({
    required this.type,
    required this.date,
    required this.grams,
    required this.pricePerGram,
  });

  double get amount => grams * pricePerGram;
}

class GoalModel {
  final String id;
  final String title;
  final String category;
  final String categoryEmoji;
  final double targetAmount;
  final double savedAmount;
  final DateTime createdAt;
  final DateTime deadline;
  final SavingFrequency frequency;
  final double installmentAmount;
  final DateTime nextDeductionDate;
  final bool autoDebitActive;
  final List<GoalContribution> contributions;
  final bool completed;

  const GoalModel({
    required this.id,
    required this.title,
    required this.category,
    required this.categoryEmoji,
    required this.targetAmount,
    required this.savedAmount,
    required this.createdAt,
    required this.deadline,
    this.frequency = SavingFrequency.monthly,
    this.installmentAmount = 0,
    required this.nextDeductionDate,
    this.autoDebitActive = true,
    this.contributions = const [],
    this.completed = false,
  });

  double get progress => targetAmount <= 0 ? 0 : (savedAmount / targetAmount).clamp(0, 1);

  // Linear pace check: how far along the goal "should" be by now, given
  // when it was created and when it's due. No real pacing data exists on
  // the backend, so this is the only honest way to derive on-track/behind
  // without a server-side field for it.
  double get _expectedProgress {
    final totalDays = deadline.difference(createdAt).inDays;
    if (totalDays <= 0) return 1;
    final elapsedDays = DateTime.now().difference(createdAt).inDays;
    return (elapsedDays / totalDays).clamp(0, 1);
  }

  bool get isOnTrack => completed || progress >= _expectedProgress;

  double get behindAmount =>
      (targetAmount * _expectedProgress - savedAmount).clamp(0, double.infinity);

  int get monthsLeft {
    final now = DateTime.now();
    final months = (deadline.year - now.year) * 12 + (deadline.month - now.month);
    return months < 0 ? 0 : months;
  }

  int get daysLeft {
    final d = deadline.difference(DateTime.now()).inDays;
    return d < 0 ? 0 : d;
  }

  double get totalGramsHeld => contributions.fold(0.0, (s, c) => s + c.grams);
  double get totalInvested => contributions.fold(0.0, (s, c) => s + c.amount);

  GoalModel copyWith({
    double? savedAmount,
    bool? completed,
    bool? autoDebitActive,
    DateTime? nextDeductionDate,
    List<GoalContribution>? contributions,
  }) =>
      GoalModel(
        id: id,
        title: title,
        category: category,
        categoryEmoji: categoryEmoji,
        targetAmount: targetAmount,
        savedAmount: savedAmount ?? this.savedAmount,
        createdAt: createdAt,
        deadline: deadline,
        frequency: frequency,
        installmentAmount: installmentAmount,
        nextDeductionDate: nextDeductionDate ?? this.nextDeductionDate,
        autoDebitActive: autoDebitActive ?? this.autoDebitActive,
        contributions: contributions ?? this.contributions,
        completed: completed ?? this.completed,
      );
}