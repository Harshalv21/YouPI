import 'package:dio/dio.dart';
import '../../core/services/api_service.dart';

class GoldRepository {
  final Dio _dio = ApiService.instance;

  /// Powers the home screen's gold coin popup ("X Coins — Worth ₹Y").
  /// A user with no rewards yet still gets a valid response (coinCount: 0,
  /// balanceRupees: 0) from the backend -- not a 404 -- so this doesn't
  /// need the same null-is-normal handling as getActiveRecharge().
  Future<GoldWalletResult> getWallet() async {
    try {
      final res = await _dio.get('/v1/gold/wallet');
      final data = ApiService.unwrap(res) as Map<String, dynamic>;
      return GoldWalletResult.fromJson(data);
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }

  /// Withdraws the given rupee amount from the gold coin balance into the
  /// user's NBFC wallet. Backend enforces the ₹50 minimum -- this just
  /// passes the amount through and surfaces whatever error comes back
  /// (e.g. MIN_WITHDRAW, INSUFFICIENT_GOLD_BALANCE).
  Future<GoldWithdrawResult> withdraw(double amountRupees) async {
    try {
      final res = await _dio.post('/v1/gold/withdraw', data: {
        'amountRupees': amountRupees,
      });
      final data = ApiService.unwrap(res) as Map<String, dynamic>;
      return GoldWithdrawResult.fromJson(data);
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }
}

class GoldWalletResult {
  final int coinCount;
  final double balanceRupees;

  GoldWalletResult({
    required this.coinCount,
    required this.balanceRupees,
  });

  factory GoldWalletResult.fromJson(Map<String, dynamic> json) => GoldWalletResult(
    coinCount: (json['coinCount'] as num?)?.toInt() ?? 0,
    balanceRupees: (json['balanceRupees'] as num?)?.toDouble() ?? 0.0,
  );
}

class GoldWithdrawResult {
  final double amountRupees;
  final double remainingBalanceRupees;
  final int remainingCoinCount;

  GoldWithdrawResult({
    required this.amountRupees,
    required this.remainingBalanceRupees,
    required this.remainingCoinCount,
  });

  factory GoldWithdrawResult.fromJson(Map<String, dynamic> json) => GoldWithdrawResult(
    amountRupees: (json['amountRupees'] as num).toDouble(),
    remainingBalanceRupees: (json['remainingBalanceRupees'] as num).toDouble(),
    remainingCoinCount: (json['remainingCoinCount'] as num).toInt(),
  );
}