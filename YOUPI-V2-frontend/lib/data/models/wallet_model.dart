// lib/data/models/wallet_model.dart
//
// Matches backend WalletBalanceResponse:
//   { userId, wallets: [ { walletId, type, balance, currency, isActive } ] }

class WalletInfo {
  final String walletId;
  final String type; // NBFC, SMART_SAVER, GOLD, FD_COLLATERAL
  final double balance;
  final String currency;
  final bool isActive;

  const WalletInfo({
    required this.walletId,
    required this.type,
    required this.balance,
    required this.currency,
    required this.isActive,
  });

  factory WalletInfo.fromJson(Map<String, dynamic> json) {
    return WalletInfo(
      walletId: json['walletId']?.toString() ?? '',
      type: json['type']?.toString() ?? 'NBFC',
      balance: _toDouble(json['balance']),
      currency: json['currency']?.toString() ?? 'INR',
      isActive: json['isActive'] == true,
    );
  }
}

class WalletBalance {
  final String userId;
  final List<WalletInfo> wallets;

  const WalletBalance({required this.userId, required this.wallets});

  factory WalletBalance.fromJson(Map<String, dynamic> json) {
    final list = (json['wallets'] as List<dynamic>? ?? [])
        .map((e) => WalletInfo.fromJson(e as Map<String, dynamic>))
        .toList();
    return WalletBalance(
      userId: json['userId']?.toString() ?? '',
      wallets: list,
    );
  }

  /// Convenience: the main spendable wallet (NBFC), or 0 if none.
  WalletInfo? get nbfc {
    for (final w in wallets) {
      if (w.type == 'NBFC') return w;
    }
    return wallets.isNotEmpty ? wallets.first : null;
  }

  double get nbfcBalance => nbfc?.balance ?? 0.0;

  WalletInfo? byType(String type) {
    for (final w in wallets) {
      if (w.type == type) return w;
    }
    return null;
  }
}

/// Safely turn backend numeric (may arrive as num or String) into double.
double _toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}