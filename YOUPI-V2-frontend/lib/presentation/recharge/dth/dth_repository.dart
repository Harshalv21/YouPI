import 'package:dio/dio.dart';
import '../../../core/services/api_service.dart';
import '../../../core/services/storage_service.dart';
import 'dth_operator_model.dart';

// Mirrors RechargeRepository's shape but hits the DTH-only router
// (DthRouter.kt: GET /dth/operators, POST /dth/order) instead of the
// mobile recharge endpoints -- so a change to one never risks the other.
//
// ApiService doesn't expose get()/post() itself -- it holds a static Dio
// (ApiService.instance) plus two helpers: unwrap() pulls the `data` field
// out of the backend's {success, data} envelope (and throws ApiException
// on {success: false}), and toException() converts a DioException into
// the same ApiException shape. Every call below follows that same
// try/catch pattern.
class DthOrderResult {
  final String orderId;
  final String? razorpayOrderId;
  final String? razorpayKeyId;
  final double? walletAmount;
  final double? gatewayAmount;
  final String? status;

  DthOrderResult({
    required this.orderId,
    this.razorpayOrderId,
    this.razorpayKeyId,
    this.walletAmount,
    this.gatewayAmount,
    this.status,
  });

  factory DthOrderResult.fromJson(Map<String, dynamic> json) {
    return DthOrderResult(
      orderId: json['orderId'] as String,
      razorpayOrderId: json['razorpayOrderId'] as String?,
      razorpayKeyId: json['razorpayKeyId'] as String?,
      walletAmount: (json['walletAmount'] as num?)?.toDouble(),
      gatewayAmount: (json['gatewayAmount'] as num?)?.toDouble(),
      status: json['status'] as String?,
    );
  }
}

class DthOrderStatus {
  final String status;
  bool get isSuccess => status.toUpperCase() == 'RECHARGE_SUCCESS' || status.toUpperCase() == 'SUCCESS';
  bool get isFailed => status.toUpperCase() == 'RECHARGE_FAILED' || status.toUpperCase() == 'FAILED';

  DthOrderStatus({required this.status});

  factory DthOrderStatus.fromJson(Map<String, dynamic> json) {
    return DthOrderStatus(status: json['status'] as String);
  }
}

// Response shape for GET /v1/recharge/dth/customer-info -- mirrors
// DthCustomerInfoResponse in DthModels.kt exactly. All fields besides
// isActive are nullable since mPlan doesn't guarantee every field is
// present on every successful response.
class DthCustomerInfo {
  final String? custId;
  final String? customerName;
  final double? monthlyRecharge;
  final double? balance;
  final String? nextRechargeDate;
  final String? status;
  final String? planName;
  final bool isActive;

  DthCustomerInfo({
    this.custId,
    this.customerName,
    this.monthlyRecharge,
    this.balance,
    this.nextRechargeDate,
    this.status,
    this.planName,
    required this.isActive,
  });

  factory DthCustomerInfo.fromJson(Map<String, dynamic> json) {
    return DthCustomerInfo(
      custId: json['custId'] as String?,
      customerName: json['customerName'] as String?,
      monthlyRecharge: (json['monthlyRecharge'] as num?)?.toDouble(),
      balance: (json['balance'] as num?)?.toDouble(),
      nextRechargeDate: json['nextRechargeDate'] as String?,
      status: json['status'] as String?,
      planName: json['planName'] as String?,
      isActive: json['isActive'] as bool? ?? false,
    );
  }
}

// A previously-used DTH account, derived client-side from
// GET /v1/recharge/history (the same shared history endpoint mobile
// recharge's "Recent Recharges" strip uses -- RechargeRouter.kt's
// getOrderHistory() doesn't filter by serviceType). Filtered here to
// serviceType == 'DTH' and deduped to the most recent order per
// (operator, subscriber number) pair, since the same subscriber can
// appear many times in history. Not a dedicated backend endpoint --
// history already carries everything needed (subscriber number lives in
// the `mobileNumber` field, same column DTH orders reuse server-side).
class DthRecentAccount {
  final String operatorName; // matches DthOperatorModel.name, e.g. "AIRTEL DIGITAL TV"
  final String subscriberNumber;
  final double lastAmount;
  final DateTime? lastRechargedAt;

  DthRecentAccount({
    required this.operatorName,
    required this.subscriberNumber,
    required this.lastAmount,
    this.lastRechargedAt,
  });
}

class DthRepository {
  Dio get _dio => ApiService.instance;

  /// Falls back to kFallbackDthOperators if the endpoint is slow/down --
  /// the operator list rarely changes, so a stale-but-working list beats
  /// a blocked screen.
  Future<List<DthOperatorModel>> getOperators() async {
    try {
      final res = await _dio.get('/v1/recharge/dth/operators');
      final list = ApiService.unwrap(res) as List;
      return list
          .map((e) => DthOperatorModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return kFallbackDthOperators;
    }
  }

  Future<DthOrderResult> createOrder({
    required String subscriberNumber,
    required String operator,
    required double amount,
    required String paymentMode, // FULL or WALLET
    required String idempotencyKey,
  }) async {
    try {
      final res = await _dio.post('/v1/recharge/dth/order', data: {
        'subscriberNumber': subscriberNumber,
        'operator': operator,
        'amount': amount,
        'paymentMode': paymentMode,
        'idempotencyKey': idempotencyKey,
      });
      final data = ApiService.unwrap(res);
      return DthOrderResult.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }

  Future<DthOrderStatus> getOrderStatus(String orderId) async {
    try {
      final res = await _dio.get('/v1/recharge/dth/order/$orderId');
      final data = ApiService.unwrap(res);
      return DthOrderStatus.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }

  /// Called as soon as the subscriber ID is confirmed (before the amount
  /// screen) -- lets DthCustomerIdScreen show "no account found" right
  /// there instead of the user discovering it after entering an amount.
  /// Hits DthRouter.kt's GET /dth/customer-info (mPlan, vc_number-keyed) --
  /// NOT the /customer-info-mobile variant, since this screen only ever
  /// has the subscriber/VC number, not the customer's mobile number.
  Future<DthCustomerInfo> getCustomerInfoByVc({
    required String vcNumber,
    required String operator,
  }) async {
    try {
      final res = await _dio.get('/v1/recharge/dth/customer-info', queryParameters: {
        'vcNumber': vcNumber,
        'operator': operator,
      });
      final data = ApiService.unwrap(res);
      return DthCustomerInfo.fromJson(data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw ApiService.toException(e);
    }
  }

  /// Powers the "Recents" section on DthOperatorSelectScreen (mirrors the
  /// mobile-recharge "Recent Recharges" strip's use of the same
  /// /v1/recharge/history endpoint). Fails soft -- returns an empty list
  /// on any error (network, parsing, etc.) rather than throwing, since a
  /// broken Recents fetch should never block the operator-select screen
  /// itself from rendering.
  Future<List<DthRecentAccount>> getRecentAccounts({int limit = 5}) async {
    try {
      final res = await _dio.get('/v1/recharge/history', queryParameters: {'page': 0});
      final list = ApiService.unwrap(res) as List;
      final hidden = await StorageService.getHiddenHistoryIds();

      final seen = <String>{};
      final recents = <DthRecentAccount>[];
      for (final e in list) {
        final json = e as Map<String, dynamic>;
        if (json['serviceType'] != 'DTH') continue;

        final orderId = json['orderId'] as String?;
        if (orderId != null && hidden.contains(orderId)) continue;

        final operatorName = json['operator'] as String?;
        // DTH subscriber/VC number reuses the `mobileNumber` column
        // server-side (see DthRechargeService.createOrder()) -- same field
        // name in the JSON response.
        final subscriberNumber = json['mobileNumber'] as String?;
        final amount = (json['planAmount'] as num?)?.toDouble();
        if (operatorName == null || subscriberNumber == null || amount == null) continue;

        // History is already newest-first (backend: ORDER BY created_at
        // DESC) -- so the first time an (operator, subscriber) pair is
        // seen here IS its most recent order. No separate sort needed.
        final key = '$operatorName|$subscriberNumber';
        if (!seen.add(key)) continue;

        recents.add(DthRecentAccount(
          operatorName: operatorName,
          subscriberNumber: subscriberNumber,
          lastAmount: amount,
          lastRechargedAt: json['createdAt'] != null
              ? DateTime.tryParse(json['createdAt'] as String)?.toLocal()
              : null,
        ));
        if (recents.length >= limit) break;
      }
      return recents;
    } catch (_) {
      return [];
    }
  }
}