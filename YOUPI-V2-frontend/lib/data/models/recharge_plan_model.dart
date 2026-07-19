class RechargePlanModel {
  final String id;
  final String operator; // 'jio' | 'airtel' | 'vi' | 'bsnl'
  final String name;
  final double price;
  final String dataPerDay;
  final int validityDays;
  final String callsInfo;
  final List<String> extras;
  final bool isPopular;
  final String tier; // 'Obsidian Prime', 'Obsidian Lite', etc.
  final List<EmiOption> emiOptions;

  const RechargePlanModel({
    required this.id,
    required this.operator,
    required this.name,
    required this.price,
    required this.dataPerDay,
    required this.validityDays,
    required this.callsInfo,
    this.extras = const [],
    this.isPopular = false,
    this.tier = '',
    this.emiOptions = const [],
  });

  bool get hasEmi => emiOptions.isNotEmpty;

  /// Maps the backend's `PlanResponse` (GET /v1/recharge/plans, sourced
  /// from mPlan) into this UI model. Backend doesn't have every UI-only
  /// field (name, isPopular, tier) since those are display concepts, not
  /// billing data -- derived here with honest fallbacks instead of
  /// pretending the backend sent them.
  factory RechargePlanModel.fromApi(Map<String, dynamic> json) {
    final amount = (json['amount'] as num?)?.toDouble() ?? 0;
    final validityRaw = (json['validity'] as String?) ?? '';
    final validityDays = int.tryParse(validityRaw.replaceAll(RegExp(r'\D'), '')) ?? 0;
    final data = (json['data'] as String?)?.trim();
    final talktime = (json['talktime'] as String?)?.trim();
    final sms = (json['sms'] as String?)?.trim();
    final description = (json['description'] as String?)?.trim() ?? '';
    final category = (json['category'] as String?)?.trim() ?? '';

    // mPlan gives us raw fields, not a marketing name -- build a readable
    // one instead of showing an internal category code like "FULLTT".
    final name = description.isNotEmpty
        ? description
        : (category.isNotEmpty ? category : 'Recharge Plan');

    // EMI split shown on the plan card is indicative only (3/6-month split
    // of the plan amount, rounded up like the backend does at order-creation
    // time in RechargeService.createOrder) -- the authoritative EMI schedule
    // is computed server-side when the order is actually placed.
    final emi3 = (amount / 3).ceilToDouble();
    final emi6 = (amount / 6).ceilToDouble();

    return RechargePlanModel(
      id: (json['planId'] as String?) ?? '',
      operator: ((json['operator'] as String?) ?? '').toLowerCase(),
      name: name,
      price: amount,
      dataPerDay: data?.isNotEmpty == true ? data! : '—',
      validityDays: validityDays,
      callsInfo: talktime?.isNotEmpty == true ? talktime! : 'Unlimited',
      extras: sms?.isNotEmpty == true ? [sms!] : const [],
      // mPlan doesn't flag "popular" plans -- left false rather than
      // guessing, until the backend/product decides a real criterion
      // (e.g. most-purchased) and starts sending it.
      isPopular: false,
      tier: category,
      emiOptions: amount > 0
          ? [
        EmiOption(months: 3, monthlyAmount: emi3, totalAmount: emi3 * 3),
        EmiOption(months: 6, monthlyAmount: emi6, totalAmount: emi6 * 6),
      ]
          : const [],
    );
  }
}

class EmiOption {
  final int months;
  final double monthlyAmount;
  final double totalAmount;
  final double fee;
  final bool isRecommended;

  const EmiOption({
    required this.months,
    required this.monthlyAmount,
    required this.totalAmount,
    this.fee = 0,
    this.isRecommended = false,
  });

  String get label => '$months EMI × ₹${monthlyAmount.toStringAsFixed(0)}/month';
  String get feeLabel => fee > 0 ? '₹${fee.toStringAsFixed(0)} fee' : '0% interest';
}