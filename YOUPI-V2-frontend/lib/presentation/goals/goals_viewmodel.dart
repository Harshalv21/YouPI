import 'package:flutter/material.dart';
import '../../data/models/goal_model.dart';

// No goals backend exists yet (see the note in invest_viewmodel.dart about
// "Open FD Now" -- same situation here, just for goals). Goals live only
// in memory for this session, seeded with two sample goals so the screen
// isn't empty on first look. Swap the in-memory list for a real
// repository call once a goals API exists.
class GoalsViewModel extends ChangeNotifier {
  late final List<GoalModel> _goals = [
    GoalModel(
      id: '1',
      title: 'New bike',
      category: 'Vehicle',
      categoryEmoji: '🚗',
      targetAmount: 120000,
      savedAmount: 74400,
      createdAt: DateTime.now().subtract(const Duration(days: 120)),
      deadline: DateTime.now().add(const Duration(days: 242)),
      frequency: SavingFrequency.monthly,
      installmentAmount: 8334,
      nextDeductionDate: DateTime.now().add(const Duration(days: 9)),
      contributions: _seedContributions(74400, 120),
    ),
    GoalModel(
      id: '2',
      title: 'Goa trip',
      category: 'Travel',
      categoryEmoji: '✈️',
      targetAmount: 30000,
      savedAmount: 8400,
      createdAt: DateTime.now().subtract(const Duration(days: 60)),
      deadline: DateTime.now().add(const Duration(days: 90)),
      frequency: SavingFrequency.monthly,
      installmentAmount: 4200,
      nextDeductionDate: DateTime.now().add(const Duration(days: 5)),
      contributions: _seedContributions(8400, 60),
    ),
  ];

  // Synthetic seed history only (for the two sample goals above) --
  // spreads the known savedAmount across a handful of past contributions
  // at plausible historical gold prices, so the detail screen's "Recent
  // contributions" and gain math have something real to compute from.
  // New goals created via CreateGoalScreen start with an empty list --
  // no auto-debit engine actually runs yet to generate real ones.
  static List<GoalContribution> _seedContributions(double totalSaved, int spanDays) {
    const count = 5;
    final perEntry = totalSaved / count;
    final basePrice = 7500.0;
    return List.generate(count, (i) {
      final daysAgo = (spanDays * (count - i) / (count + 1)).round();
      final price = basePrice + (i * 35); // gently rising historical price
      return GoalContribution(
        type: i == 2 ? 'Manual top-up' : 'Auto-debit',
        date: DateTime.now().subtract(Duration(days: daysAgo)),
        grams: perEntry / price,
        pricePerGram: price,
      );
    });
  }

  List<GoalModel> get activeGoals => _goals.where((g) => !g.completed).toList();
  List<GoalModel> get completedGoals => _goals.where((g) => g.completed).toList();
  double get totalSaved => _goals.fold(0.0, (sum, g) => sum + g.savedAmount);

  GoalModel? goalById(String id) {
    for (final g in _goals) {
      if (g.id == id) return g;
    }
    return null;
  }

  void addGoal({
    required String title,
    required String category,
    required String categoryEmoji,
    required double targetAmount,
    required DateTime deadline,
    required SavingFrequency frequency,
    double installmentAmount = 0,
  }) {
    final now = DateTime.now();
    _goals.add(GoalModel(
      id: now.millisecondsSinceEpoch.toString(),
      title: title,
      category: category,
      categoryEmoji: categoryEmoji,
      targetAmount: targetAmount,
      savedAmount: 0,
      createdAt: now,
      deadline: deadline,
      frequency: frequency,
      installmentAmount: installmentAmount,
      nextDeductionDate: _nextDeduction(now, frequency),
    ));
    notifyListeners();
  }

  static DateTime _nextDeduction(DateTime from, SavingFrequency f) {
    switch (f) {
      case SavingFrequency.daily:
        return from.add(const Duration(days: 1));
      case SavingFrequency.weekly:
        return from.add(const Duration(days: 7));
      case SavingFrequency.monthly:
        return DateTime(from.year, from.month + 1, from.day);
    }
  }

  // "Add money" on the goal detail screen -- records a real contribution
  // (grams bought at today's live price) rather than just bumping a
  // number, so gain stays honestly derived from cost basis.
  void addContribution(String goalId, double amount, double pricePerGram) {
    final index = _goals.indexWhere((g) => g.id == goalId);
    if (index == -1 || pricePerGram <= 0) return;
    final goal = _goals[index];
    final contribution = GoalContribution(
      type: 'Manual top-up',
      date: DateTime.now(),
      grams: amount / pricePerGram,
      pricePerGram: pricePerGram,
    );
    _goals[index] = goal.copyWith(
      savedAmount: goal.savedAmount + amount,
      contributions: [contribution, ...goal.contributions],
    );
    notifyListeners();
  }

  void toggleAutoDebit(String goalId) {
    final index = _goals.indexWhere((g) => g.id == goalId);
    if (index == -1) return;
    final goal = _goals[index];
    _goals[index] = goal.copyWith(autoDebitActive: !goal.autoDebitActive);
    notifyListeners();
  }

  void deleteGoal(String goalId) {
    _goals.removeWhere((g) => g.id == goalId);
    notifyListeners();
  }
}