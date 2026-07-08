import '../datasources/mock_data.dart';
import '../models/recharge_plan_model.dart';

class RechargeRepository {
  Future<List<RechargePlanModel>> getPlans({String? operator}) async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (operator != null) {
      return MockData.mockRechargePlans
          .where((p) => p.operator == operator)
          .toList();
    }
    return MockData.mockRechargePlans;
  }

  Future<List<RechargePlanModel>> searchPlans(String query) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final q = query.toLowerCase();
    return MockData.mockRechargePlans.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.price.toString().contains(q) ||
          p.dataPerDay.toLowerCase().contains(q) ||
          p.validityDays.toString().contains(q);
    }).toList();
  }

  Future<Map<String, String>> detectOperator(String mobile) async {
    await Future.delayed(const Duration(milliseconds: 700));
    return {'operator': 'airtel', 'circle': 'UP East'};
  }

  Future<bool> processRecharge({
    required String mobile,
    required RechargePlanModel plan,
    EmiOption? emiOption,
  }) async {
    await Future.delayed(const Duration(milliseconds: 1500));
    return true;
  }
}
