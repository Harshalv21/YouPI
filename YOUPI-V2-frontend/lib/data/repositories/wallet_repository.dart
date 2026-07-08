// lib/data/repositories/wallet_repository.dart
//
// Real backend-connected wallet repository.
// Endpoints (all require Bearer token — added automatically by ApiService):
//   GET  /v1/wallet/balance
//   GET  /v1/wallet/ledger?type=NBFC&page=0
//   POST /v1/wallet/transfer

import 'package:dio/dio.dart';
import '../../core/services/api_service.dart';
import '../models/wallet_model.dart';
import '../models/transaction_model.dart';

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

  /// P2P transfer to another user by mobile number.
  /// idempotencyKey prevents double-charges on retry — generate a fresh one per attempt.
  Future<WalletInfo> transfer({
    required String recipientMobile,
    required double amount,
    required String idempotencyKey,
    String walletType = 'NBFC',
    String? description,
  }) async {
    try {
      final res = await _dio.post('/v1/wallet/transfer', data: {
        'recipientMobile': recipientMobile,
        'amount': amount,
        'walletType': walletType,
        'description': description,
        'idempotencyKey': idempotencyKey,
      });
      final data = ApiService.unwrap(res); // -> TransferResponse
      // Return the sender's updated balance.
      return WalletInfo.fromJson(
          (data as Map<String, dynamic>)['senderBalance'] as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }
}