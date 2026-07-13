// lib/data/repositories/invest_repository.dart
//
// Gold: real backend-connected (Augmont-integrated).
//   GET  /v1/gold/price     -- live buy/sell rates
//   GET  /v1/gold/holdings  -- real balance (grams + value)
//   POST /v1/gold/buy
//   POST /v1/gold/sell
//
// FD calculator: deliberately stays client-side math (FdModel.calculateMaturity).
// The backend's only "create FD" endpoint (/v1/fd/create) is Gold-FD --
// it takes a gold WEIGHT, not a cash amount, and doesn't match this
// rupee-based calculator/partner-bank UI at all. There's no cash-based FD
// creation endpoint on the backend yet ("legacy" /v1/fd/list only reads,
// never writes). So "Open FD Now" is intentionally locked (Coming Soon)
// rather than wired to a real call that doesn't exist -- wiring it to
// anything else would either silently do nothing or hit the wrong
// (weight-based) endpoint with cash figures, which would be worse than
// leaving it locked.

import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import '../../core/services/api_service.dart';
import '../models/gold_model.dart';
import '../models/loan_model.dart';

class InvestRepository {
  final Dio _dio = ApiService.instance;

  /// Live gold buy/sell rates from Augmont (cached server-side for 35s).
  Future<GoldModel> getGoldPrice() async {
    try {
      final res = await _dio.get('/v1/gold/price');
      final data = ApiService.unwrap(res) as Map<String, dynamic>;
      final buyRate = double.parse(data['goldBuyRate'].toString());
      final sellRate = double.parse(data['goldSellRate'].toString());
      return GoldModel(
        pricePerGram: buyRate,
        sellRatePerGram: sellRate,
        // Backend doesn't return a day-over-day % change yet -- showing 0
        // rather than a fabricated number until that's built.
        priceChange: 0,
        isPriceUp: true,
        lastUpdated: DateTime.now(),
      );
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }

  /// Real gold holdings (grams + current INR value), separate call since
  /// price and holdings are two different backend concerns.
  Future<GoldModel> getGoldHoldings(GoldModel priceSnapshot) async {
    try {
      final res = await _dio.get('/v1/gold/holdings');
      final data = ApiService.unwrap(res) as Map<String, dynamic>;
      return priceSnapshot.copyWith(
        balanceGrams: double.parse(data['totalGrams'].toString()),
        balanceValue: double.parse(data['currentValue'].toString()),
        totalInvested: double.parse(data['totalInvested'].toString()),
      );
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }

  /// The backend's buyGold()/sellGold() throw AugmontUserNotMappedException
  /// if this user has never been mapped to an Augmont account -- and
  /// nothing in the backend calls this automatically (checked: not on
  /// registration, not on KYC completion). So the Gold screen calls this
  /// once, best-effort, before allowing a transaction. The backend's
  /// ensureAugmontUser() already checks for an existing mapping first, so
  /// repeated calls here are cheap and safe -- this is NOT re-creating the
  /// account every time.
  Future<void> ensureAugmontUser({
    required String name,
    required String email,
    required String mobile,
  }) async {
    try {
      await _dio.post('/v1/gold/user', data: {
        'userName': name,
        'userEmail': email,
        'userMobile': mobile,
      });
    } on DioException {
      // Best-effort -- if this fails (e.g. already mapped and backend
      // returns a non-201 some other way, or a transient network issue),
      // don't block the screen. The actual buy/sell call will surface a
      // clear error if the account genuinely isn't mapped.
    }
  }

  /// Generates a fresh idempotency key per attempt -- required by the
  /// backend so a retried/duplicated request can't buy/sell twice.
  String _newIdempotencyKey() {
    final random = Random.secure();
    final seed = List<int>.generate(24, (_) => random.nextInt(256));
    return sha256.convert(seed).toString();
  }

  Future<bool> buyGold(double amountInr) async {
    try {
      final res = await _dio.post('/v1/gold/buy', data: {
        'amount': amountInr,
        'idempotencyKey': _newIdempotencyKey(),
        'metalType': 'gold',
      });
      return ApiService.unwrap(res) != null;
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }

  Future<bool> sellGold(double grams) async {
    try {
      final res = await _dio.post('/v1/gold/sell', data: {
        'grams': grams,
        'idempotencyKey': _newIdempotencyKey(),
        'metalType': 'gold',
      });
      return ApiService.unwrap(res) != null;
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }

  // ── FD calculator: pure client-side math, see file header ──
  Future<double> calculateFdMaturity(
      double principal, double rate, int months) async {
    return FdModel.calculateMaturity(principal, rate, months);
  }
}

class BnplRepository {
  Future<bool> applyForBnpl({
    required double income,
    required String employmentType,
    required String pan,
  }) async {
    await Future.delayed(const Duration(milliseconds: 2000));
    return income >= 15000; // approve if income >= 15000
  }

  Future<bool> createSmartDeposit(double amount) async {
    await Future.delayed(const Duration(milliseconds: 1200));
    return true;
  }
}