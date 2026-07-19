// lib/data/repositories/recharge_repository.dart
//
// Real backend-connected recharge repository.
// Endpoints (all require Bearer token — added automatically by ApiService):
//   GET  /v1/recharge/plans?operator=X&circle=Y
//   POST /v1/recharge/order
//   GET  /v1/recharge/order/{orderId}
//   POST /v1/recharge/order/{orderId}/confirm   (status-check only now, see below)
//   GET  /v1/recharge/history

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
  ///
  /// NOTE: this only creates the order -- it does NOT open the Razorpay
  /// payment sheet. `razorpay_flutter` isn't wired into this app anywhere
  /// yet (checked across the whole codebase), so actually collecting
  /// payment is a separate integration step. Wire that before calling this
  /// in production, otherwise you'll create orders that never get paid.
  Future<RechargeOrderResult> createOrder({
    required String mobileNumber,
    required String operator,
    required String circle,
    required String planId,
    required double planAmount,
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
  // PAYMENT_DONE = payment confirmed via webhook, but actual delivery to
  // the operator isn't wired yet (A1Topup pending); RECHARGE_SUCCESS will
  // mean delivery also confirmed once that's implemented.
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