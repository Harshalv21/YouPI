class BnplModel {
  final String id;
  final double limit;
  final double used;
  final bool isApproved;
  final String cardNumber; // masked
  final String cardHolderName;
  final String status; // 'active' | 'pending' | 'rejected'

  const BnplModel({
    required this.id,
    required this.limit,
    required this.used,
    required this.isApproved,
    this.cardNumber = '•••• •••• •••• 8824',
    this.cardHolderName = 'RAHUL SHARMA',
    this.status = 'pending',
  });

  double get available => limit - used;
  double get usedPercent => limit > 0 ? used / limit : 0;
}
