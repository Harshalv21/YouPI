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