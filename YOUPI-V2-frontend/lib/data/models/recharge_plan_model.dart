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
