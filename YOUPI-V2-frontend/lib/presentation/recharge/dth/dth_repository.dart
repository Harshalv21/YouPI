import 'package:dio/dio.dart';
import '../../../core/services/api_service.dart';
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
}