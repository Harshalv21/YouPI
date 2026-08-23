class TransactionModel {
  final String id;
  final String title;
  final String category;
  final String type; // 'credit' | 'debit' | 'investment'
  final double amount;
  final DateTime dateTime;
  final String status; // 'completed' | 'pending' | 'failed'
  final String? note;

  const TransactionModel({
    required this.id,
    required this.title,
    required this.category,
    required this.type,
    required this.amount,
    required this.dateTime,
    required this.status,
    this.note,
  });

  bool get isCredit => type == 'credit';
  bool get isDebit => type == 'debit';
  bool get isInvestment => type == 'investment';

  // ← NAYA: backend split-recharge ka wallet/gateway breakdown alag fields
  // mein nahi bhejta -- sab kuch ek free-text `description` (jo yaha
  // `title` ban jaata hai) ke andar hota hai, jaise:
  // "Split recharge 9867123027 (wallet portion ₹12.0 of ₹33)".
  // Isko parse karke structured details nikalte hai -- list-row ko
  // simplify karne aur detail bottom-sheet mein breakdown dikhane, dono
  // ke liye use hota hai. Backend format badla to sirf yaha regex update
  // karna padega.
  SplitRechargeDetails? get splitRechargeDetails =>
      SplitRechargeDetails.tryParse(title);

  /// Maps a backend ledger_entries row to this UI model.
  ///
  /// Backend fields:
  ///   { id, walletId, txnDirection: CREDIT|DEBIT, amount, balanceBefore,
  ///     balanceAfter, referenceType, referenceId, description, createdAt }
  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    final direction =
    (json['txnDirection'] ?? '').toString().toUpperCase();
    final refType = (json['referenceType'] ?? '').toString();

    return TransactionModel(
      id: json['id']?.toString() ?? '',
      // Backend has no "title" — use description, else a friendly refType.
      title: (json['description'] as String?)?.trim().isNotEmpty == true
          ? json['description'] as String
          : _titleFromRef(refType),
      category: _categoryFromRef(refType),
      type: _mapType(direction, refType),
      amount: _toDouble(json['amount']),
      dateTime: _parseDate(json['createdAt']),
      // Ledger entries are always settled (immutable), so completed.
      status: 'completed',
      note: refType.isNotEmpty ? refType : null,
    );
  }

  // CREDIT/DEBIT + reference type → UI type.
  static String _mapType(String direction, String refType) {
    final r = refType.toUpperCase();
    if (r.contains('GOLD') ||
        r.contains('FD') ||
        r.contains('INVEST') ||
        r.contains('SMART_SAVER')) {
      return 'investment';
    }
    return direction == 'CREDIT' ? 'credit' : 'debit';
  }

  static String _titleFromRef(String refType) {
    switch (refType.toUpperCase()) {
      case 'P2P_SEND':
        return 'Money Sent';
      case 'P2P_RECEIVE':
        return 'Money Received';
      case 'RECHARGE':
        return 'Mobile Recharge';
      case 'GOLD_BUY':
        return 'Digital Gold Purchase';
      case 'GOLD_SELL':
        return 'Digital Gold Sale';
      case 'ADD_MONEY':
        return 'Wallet Top-up';
      case 'WITHDRAW':
        return 'Withdrawal';
      default:
        return refType.isEmpty ? 'Transaction' : _prettify(refType);
    }
  }

  static String _categoryFromRef(String refType) {
    final r = refType.toUpperCase();
    if (r.contains('P2P')) return 'Transfer';
    if (r.contains('RECHARGE')) return 'Recharge';
    if (r.contains('GOLD')) return 'Wealth';
    if (r.contains('FD') || r.contains('INVEST')) return 'Investment';
    if (r.contains('BNPL')) return 'BNPL';
    if (r.contains('LOAN')) return 'Loan';
    return 'Wallet';
  }

  static String _prettify(String s) => s
      .toLowerCase()
      .split('_')
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

double _toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

DateTime _parseDate(dynamic v) {
  if (v == null) return DateTime.now();
  return DateTime.tryParse(v.toString())?.toLocal() ?? DateTime.now();
}

/// Parsed wallet/gateway breakdown for a split-recharge transaction.
/// Only non-null when [TransactionModel.title] matches the backend's
/// "Split recharge <mobile> (wallet portion ₹X of ₹Y)" description format.
class SplitRechargeDetails {
  final String mobileNumber;
  final double walletPortion;
  final double totalAmount;

  const SplitRechargeDetails({
    required this.mobileNumber,
    required this.walletPortion,
    required this.totalAmount,
  });

  double get gatewayPortion => totalAmount - walletPortion;

  static final RegExp _pattern = RegExp(
    r'split recharge\s+(\d+)\s*\(wallet portion\s*₹?([\d.]+)\s*of\s*₹?([\d.]+)\)',
    caseSensitive: false,
  );

  static SplitRechargeDetails? tryParse(String text) {
    final match = _pattern.firstMatch(text);
    if (match == null) return null;
    final wallet = double.tryParse(match.group(2) ?? '');
    final total = double.tryParse(match.group(3) ?? '');
    if (wallet == null || total == null) return null;
    return SplitRechargeDetails(
      mobileNumber: match.group(1) ?? '',
      walletPortion: wallet,
      totalAmount: total,
    );
  }
}