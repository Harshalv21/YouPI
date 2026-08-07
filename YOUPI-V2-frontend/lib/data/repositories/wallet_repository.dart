// lib/data/repositories/wallet_repository.dart
//
// Real backend-connected wallet repository.
// Endpoints (all require Bearer token — added automatically by ApiService):
//   GET  /v1/wallet/balance
//   GET  /v1/wallet/ledger?type=NBFC&page=0
//   POST /v1/wallet/topup/order
//   GET  /v1/wallet/topup/order/{orderId}/status
//
// NOTE: transfer() (P2P send-money) was removed along with the backend
// endpoint -- wallet MVP is closed-loop by design (G1/G2 guardrails: no
// withdraw, no send money, no wallet-to-wallet transfer). Spend is only
// possible via a service the backend allowlists (currently just RECHARGE).

import 'package:dio/dio.dart';
import '../../core/services/api_service.dart';
import '../models/wallet_model.dart';
import '../models/transaction_model.dart';

class WalletTopupOrder {
  final String orderId;          // Cashfree order id
  final String paymentSessionId; // needed by CashfreeService.open()
  final int amountPaise;
  final String currency;
  final String? receipt;

  const WalletTopupOrder({
    required this.orderId,
    required this.paymentSessionId,
    required this.amountPaise,
    required this.currency,
    this.receipt,
  });

  factory WalletTopupOrder.fromJson(Map<String, dynamic> json) {
    return WalletTopupOrder(
      orderId: json['orderId']?.toString() ?? '',
      paymentSessionId: json['paymentSessionId']?.toString() ?? '',
      amountPaise: (json['amount'] as num?)?.toInt() ?? 0,
      currency: json['currency']?.toString() ?? 'INR',
      receipt: json['receipt']?.toString(),
    );
  }
}

class WalletTopupStatus {
  final String orderId;
  final String status; // CREATED, PENDING, CAPTURED, FAILED, REFUNDED, DISPUTED
  final int amountPaise;

  const WalletTopupStatus({
    required this.orderId,
    required this.status,
    required this.amountPaise,
  });

  factory WalletTopupStatus.fromJson(Map<String, dynamic> json) {
    return WalletTopupStatus(
      orderId: json['orderId']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      amountPaise: (json['amount'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isCaptured => status == 'CAPTURED';
  bool get isFailed => status == 'FAILED' || status == 'DISPUTED';
}

class WalletRepository {
  final Dio _dio = ApiService.instance;

  /// All wallet balances (NBFC, GOLD, SMART_SAVER, FD_COLLATERAL).
  Future<WalletBalance> getBalance() async {
    try {
      final res = await _dio.get('/v1/wallet/balance');
      final data = ApiService.unwrap(res); // -> { userId, wallets: [...] }
      return WalletBalance.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }

  /// Convenience: just the primary (NBFC) spendable balance as a number.
  Future<double> getNbfcBalance() async {
    final wallet = await getBalance();
    return wallet.nbfcBalance;
  }

  /// Transaction history (ledger) for a wallet type, paginated.
  Future<List<TransactionModel>> getLedger({
    String type = 'NBFC',
    int page = 0,
  }) async {
    try {
      final res = await _dio.get('/v1/wallet/ledger', queryParameters: {
        'type': type,
        'page': page,
      });
      final data = ApiService.unwrap(res); // -> List of ledger entries
      final list = (data as List<dynamic>? ?? []);
      return list
          .map((e) => TransactionModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }

  /// Creates a real Cashfree order to add money to the NBFC wallet.
  /// Returns orderId + paymentSessionId for CashfreeService.open().
  Future<WalletTopupOrder> createTopupOrder(double amountRupees) async {
    try {
      final res = await _dio.post('/v1/wallet/topup/order', data: {
        'amountRupees': amountRupees,
      });
      final data = ApiService.unwrap(res);
      return WalletTopupOrder.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }

  /// Polled after Cashfree checkout closes, to confirm the wallet was
  /// actually credited (same pattern as RechargeRepository.getOrderStatus()).
  Future<WalletTopupStatus> getTopupOrderStatus(String orderId) async {
    try {
      final res = await _dio.get('/v1/wallet/topup/order/$orderId/status');
      final data = ApiService.unwrap(res);
      return WalletTopupStatus.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }
}