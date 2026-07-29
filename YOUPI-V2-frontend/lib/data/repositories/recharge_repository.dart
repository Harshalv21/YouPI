// lib/data/repositories/recharge_repository.dart
//
// Real backend-connected recharge repository.
// Endpoints (all require Bearer token — added automatically by ApiService):
//   GET  /v1/recharge/plans?operator=X&circle=Y
//   POST /v1/recharge/order
//   GET  /v1/recharge/order/{orderId}
//   POST /v1/recharge/order/{orderId}/confirm   (status-check only now, see below)
//   GET  /v1/recharge/history
//   GET  /v1/recharge/active

import 'package:dio/dio.dart';
import '../../core/services/api_service.dart';
import '../models/recharge_plan_model.dart';

class RechargeRepository {
  final Dio _dio = ApiService.instance;

  Future<List<RechargePlanModel>> getPlans({
    required String operator,
    required String circle,
  }) async {
    try {
      final res = await _dio.get('/v1/recharge/plans', queryParameters: {
        'operator': operator,
        'circle': circle,
      });
      final data = ApiService.unwrap(res); // -> List<PlanResponse>
      final list = (data as List<dynamic>? ?? []);
      return list
          .map((e) => RechargePlanModel.fromApi(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }

  /// Client-side filter over whatever's already loaded -- matches the old
  /// mock behaviour (no dedicated backend search endpoint for plans yet).
  Future<List<RechargePlanModel>> searchPlans(
      String query,
      List<RechargePlanModel> loadedPlans,
      ) async {
    final q = query.toLowerCase();
    return loadedPlans.where((p) {
      return p.name.toLowerCase().contains(q) ||
          p.price.toString().contains(q) ||
          p.dataPerDay.toLowerCase().contains(q) ||
          p.validityDays.toString().contains(q);
    }).toList();
  }

  /// Creates the Razorpay order for a recharge on the backend. Returns the
  /// fields the Razorpay Checkout SDK needs (razorpayOrderId, amount, keyId)
  /// plus our internal orderId to poll status against afterwards.
  Future<RechargeOrderResult> createOrder({
    required String mobileNumber,
    required String operator,
    required String circle,
    required String planId,
    required double planAmount,
    // Needed so the backend can compute expiry_date once the recharge
    // succeeds -- without this, "Active Recharge" on the home screen has
    // no way to know when the plan actually expires.
    required int validityDays,
    required String paymentMode, // 'FULL' | 'EMI_3' | 'EMI_6' | 'EMI_12'
    required String idempotencyKey,
  }) async {
    try {
      final res = await _dio.post('/v1/recharge/order', data: {
        'mobileNumber': mobileNumber,
        'operator': operator,
        'circle': circle,
        'planId': planId,
        'planAmount': planAmount,
        'planValidityDays': validityDays,
        'paymentMode': paymentMode,
        'idempotencyKey': idempotencyKey,
      });
      final data = ApiService.unwrap(res) as Map<String, dynamic>;
      return RechargeOrderResult.fromJson(data);
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }

  /// Polls the current state of a recharge order. This does NOT grant
  /// success itself -- only the Razorpay webhook (server-side) does that
  /// now. Call this after Razorpay Checkout closes to find out what the
  /// webhook has recorded so far; if still INITIATED, poll again for a few
  /// seconds before showing a failure/timeout state.
  Future<RechargeStatusResult> getOrderStatus(String orderId) async {
    try {
      final res = await _dio.get('/v1/recharge/order/$orderId');
      final data = ApiService.unwrap(res) as Map<String, dynamic>;
      return RechargeStatusResult.fromJson(data);
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }

  Future<List<RechargeStatusResult>> getHistory({int page = 0}) async {
    try {
      final res = await _dio.get('/v1/recharge/history', queryParameters: {
        'page': page,
      });
      final data = ApiService.unwrap(res);
      final list = (data as List<dynamic>? ?? []);
      return list
          .map((e) => RechargeStatusResult.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }

  /// Powers the home screen's "Active Recharge" card. Returns null when
  /// the user has no currently-active (not-yet-expired) recharge -- that's
  /// a normal state, not an error, so it's handled as a plain null return
  /// rather than throwing.
  Future<ActiveRechargeResult?> getActiveRecharge() async {
    try {
      final res = await _dio.get('/v1/recharge/active');
      final data = ApiService.unwrap(res);
      if (data == null) return null;
      return ActiveRechargeResult.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }
}

class RechargeOrderResult {
  final String orderId;
  final String razorpayOrderId;
  final double amount;
  final String status;
  final String paymentMode;

  RechargeOrderResult({
    required this.orderId,
    required this.razorpayOrderId,
    required this.amount,
    required this.status,
    required this.paymentMode,
  });

  factory RechargeOrderResult.fromJson(Map<String, dynamic> json) => RechargeOrderResult(
    orderId: json['orderId'] as String,
    razorpayOrderId: json['razorpayOrderId'] as String? ?? '',
    amount: (json['amount'] as num).toDouble(),
    status: json['status'] as String,
    paymentMode: json['paymentMode'] as String,
  );
}

class RechargeStatusResult {
  final String orderId;
  final String status;
  final String? mobileNumber;
  final String? operator;
  final double? planAmount;
  final String? a1TopupStatus;
  final String? goldTxnId;

  RechargeStatusResult({
    required this.orderId,
    required this.status,
    this.mobileNumber,
    this.operator,
    this.planAmount,
    this.a1TopupStatus,
    this.goldTxnId,
  });

  // Matches the backend's actual status enum (chk_recharge_status:
  // INITIATED/PAYMENT_DONE/RECHARGE_PENDING/RECHARGE_SUCCESS/
  // RECHARGE_FAILED/REFUNDED) -- there's no plain 'SUCCESS' value.
  bool get isSuccess => status == 'PAYMENT_DONE' || status == 'RECHARGE_SUCCESS';
  bool get isPending => status == 'INITIATED';
  bool get isFailed => status == 'RECHARGE_FAILED';

  factory RechargeStatusResult.fromJson(Map<String, dynamic> json) => RechargeStatusResult(
    orderId: json['orderId'] as String,
    status: json['status'] as String,
    mobileNumber: json['mobileNumber'] as String?,
    operator: json['operator'] as String?,
    planAmount: (json['planAmount'] as num?)?.toDouble(),
    a1TopupStatus: json['a1TopupStatus'] as String?,
    goldTxnId: json['goldTxnId'] as String?,
  );
}

/// The user's current active recharge -- backs the home screen status
/// card. Mirrors the backend's ActiveRechargeResponse.
class ActiveRechargeResult {
  final String orderId;
  final String mobileNumber;
  final String operator;
  final double planAmount;
  final DateTime expiryDate;
  final int daysRemaining;

  ActiveRechargeResult({
    required this.orderId,
    required this.mobileNumber,
    required this.operator,
    required this.planAmount,
    required this.expiryDate,
    required this.daysRemaining,
  });

  factory ActiveRechargeResult.fromJson(Map<String, dynamic> json) => ActiveRechargeResult(
    orderId: json['orderId'] as String,
    mobileNumber: json['mobileNumber'] as String,
    operator: json['operator'] as String,
    planAmount: (json['planAmount'] as num).toDouble(),
    expiryDate: DateTime.parse(json['expiryDate'] as String),
    daysRemaining: (json['daysRemaining'] as num).toInt(),
  );
}