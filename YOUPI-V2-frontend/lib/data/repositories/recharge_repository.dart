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
import '../../core/services/storage_service.dart';
import '../models/recharge_plan_model.dart';
import '../../presentation/recharge/recharge_history_screen.dart' show RechargeRecord, RechargeStatus;

class RechargeRepository {
  final Dio _dio = ApiService.instance;

  /// Detects the real operator/circle for a mobile number via mPlan's HLR
  /// API (backend-side). Values come back already normalized to match
  /// what getPlans() expects (e.g. "JIO", "UP EAST") -- no further mapping
  /// needed on the Flutter side.
  Future<OperatorDetectionResult> detectOperator(String mobileNumber) async {
    try {
      final res = await _dio.get('/v1/recharge/operator', queryParameters: {
        'mobile': mobileNumber,
      });
      final data = ApiService.unwrap(res) as Map<String, dynamic>;
      return OperatorDetectionResult.fromJson(data);
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }

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

  /// Plural: ALL of the user's currently-active recharges, for the home
  /// screen's horizontally-scrollable strip. Backend already filters out
  /// expired ones (WHERE expiry_date >= CURRENT_DATE) and sorts
  /// soonest-expiring first, so a recharge that expired overnight is
  /// simply absent from this list the next time it's called -- no
  /// client-side expiry bookkeeping needed.
  Future<List<ActiveRechargeResult>> getActiveRecharges() async {
    try {
      final res = await _dio.get('/v1/recharge/active/all');
      final data = ApiService.unwrap(res);
      final list = (data as List<dynamic>? ?? []);
      return list.map((e) => ActiveRechargeResult.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }

  // -------------------------------------------------------------------
  // Recharge History screen support (NEW)
  // -------------------------------------------------------------------
  // Both of these reuse the existing GET /v1/recharge/history endpoint --
  // no new backend route needed right now. They just map
  // RechargeStatusResult -> RechargeRecord (the model the History UI
  // widgets expect) and, for "recent", filter down to one mobile number.
  //
  // IMPORTANT LIMITATION: RechargeStatusResult (as returned today) doesn't
  // carry circle, validity text, paymentMethod, the Razorpay txn id,
  // createdAt, failureReason, or goldCoinsEarned. Until the backend's
  // /v1/recharge/history response is enriched with those fields, this
  // mapper fills them with safe placeholders so the UI still renders
  // without crashing. Ping backend (Laksh/Bhupinder) to add these fields
  // to RechargeHistoryResponse when convenient -- then just delete the
  // placeholder lines below and map the real fields.

  /// Last [limit] recharges for the logged-in user across ALL numbers
  /// they've ever recharged (not just the number currently typed into the
  /// mobile field). Backend already returns history newest-first.
  /// Filters out anything the user has "cleared" (StorageService's
  /// on-device hidden list) BEFORE taking the limit, so a hidden entry
  /// doesn't silently eat one of the visible slots.
  Future<List<RechargeRecord>> getRecentRecharges({int limit = 4}) async {
    final all = await getHistory();
    final hidden = await StorageService.getHiddenHistoryIds();
    return all
        .map(_toRechargeRecord)
        .where((r) => !hidden.contains(r.id))
        .take(limit)
        .toList();
  }

  Future<List<RechargeRecord>> getAllRechargeHistory({int page = 0}) async {
    final all = await getHistory(page: page);
    final hidden = await StorageService.getHiddenHistoryIds();
    return all
        .map(_toRechargeRecord)
        .where((r) => !hidden.contains(r.id))
        .toList();
  }

  /// "Clears" recharge history from view -- on-device only, see
  /// StorageService's _keyHiddenHistoryIds doc comment for why this never
  /// touches the backend records themselves.
  Future<void> hideFromHistory(Iterable<String> orderIds) async {
    await StorageService.hideHistoryIds(orderIds);
  }

  RechargeRecord _toRechargeRecord(RechargeStatusResult r) {
    return RechargeRecord(
      id: r.orderId,
      mobileNumber: r.mobileNumber ?? '',
      operator: r.operator ?? '',
      circle: '', // TODO: backend to add `circle` to RechargeHistoryResponse
      amount: r.planAmount ?? 0,
      planDescription: r.operator ?? '', // TODO: backend to add plan name/desc
      validity: '', // TODO: backend to add validityDays/label
      paymentMethod: 'Cashfree',
      paymentTxnId: r.orderId, // TODO: swap for actual Razorpay payment id once backend exposes it
      status: _mapStatus(r),
      failureReason: r.isFailed ? 'Recharge failed. Contact support if amount was deducted.' : null,
      goldCoinsEarned: null, // TODO: backend to add goldCoinsEarned to RechargeHistoryResponse
      createdAt: DateTime.now(), // TODO: backend to add createdAt/timestamp to RechargeHistoryResponse
    );
  }

  RechargeStatus _mapStatus(RechargeStatusResult r) {
    if (r.isSuccess) return RechargeStatus.success;
    if (r.isFailed) return RechargeStatus.failed;
    return RechargeStatus.pending;
  }
}

class RechargeOrderResult {
  final String orderId;
  final String razorpayOrderId;
  final String? paymentSessionId;   // NEW -- Cashfree only, null for Razorpay
  final double amount;
  final String status;
  final String paymentMode;

  RechargeOrderResult({
    required this.orderId,
    required this.razorpayOrderId,
    this.paymentSessionId,
    required this.amount,
    required this.status,
    required this.paymentMode,
  });

  factory RechargeOrderResult.fromJson(Map<String, dynamic> json) => RechargeOrderResult(
    orderId: json['orderId'] as String,
    razorpayOrderId: json['razorpayOrderId'] as String? ?? '',
    paymentSessionId: json['paymentSessionId'] as String?,
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

/// Result of operator/circle detection -- backs the slot-machine reveal
/// animation on the recharge home screen.
class OperatorDetectionResult {
  final String operator;
  final String circle;

  OperatorDetectionResult({required this.operator, required this.circle});

  factory OperatorDetectionResult.fromJson(Map<String, dynamic> json) => OperatorDetectionResult(
    operator: json['operator'] as String,
    circle: json['circle'] as String,
  );
}