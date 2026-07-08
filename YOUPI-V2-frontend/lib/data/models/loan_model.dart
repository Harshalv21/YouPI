class FdModel {
  final String id;
  final double principal;
  final double interestRate;
  final int tenureMonths;
  final DateTime startDate;
  final DateTime maturityDate;
  final double maturityAmount;
  final String status; // 'active' | 'matured' | 'closed'

  const FdModel({
    required this.id,
    required this.principal,
    required this.interestRate,
    required this.tenureMonths,
    required this.startDate,
    required this.maturityDate,
    required this.maturityAmount,
    this.status = 'active',
  });

  double get interestEarned => maturityAmount - principal;

  static double calculateMaturity(double principal, double rate, int months) {
    final years = months / 12;
    return principal * (1 + (rate / 100) * years);
  }
}

class LoanModel {
  final String id;
  final double amount;
  final double interestRate;
  final int tenureMonths;
  final double monthlyEmi;
  final double totalPayable;
  final int emisPaid;
  final DateTime nextEmiDate;
  final String status; // 'active' | 'closed' | 'overdue'
  final String bankName;
  final String maskedAccountNumber;

  const LoanModel({
    required this.id,
    required this.amount,
    required this.interestRate,
    required this.tenureMonths,
    required this.monthlyEmi,
    required this.totalPayable,
    required this.emisPaid,
    required this.nextEmiDate,
    this.status = 'active',
    this.bankName = 'Axis Bank',
    this.maskedAccountNumber = '•••• 4521',
  });

  int get emisRemaining => tenureMonths - emisPaid;
  double get progressPercent => emisPaid / tenureMonths;
}
