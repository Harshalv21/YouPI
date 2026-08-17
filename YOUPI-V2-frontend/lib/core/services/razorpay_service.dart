// lib/core/services/razorpay_service.dart
//
// Thin async/await wrapper around razorpay_flutter's callback-based API,
// mirroring the (now-removed) CashfreeService's shape so
// recharge_viewmodel.dart / add_money_screen.dart's call sites need
// minimal changes going back to Razorpay.
//
// SECURITY NOTE (same as the Cashfree service this replaces): the SDK's
// success callback means ONLY "the checkout sheet completed and returned
// a paymentId/signature" -- it does NOT mean the recharge/top-up was
// granted. The caller MUST still poll the backend's order-status endpoint
// and wait for Razorpay's webhook (POST /webhooks/razorpay) to confirm
// server-side. Do not shortcut that here.
//
// Cancel detection: Razorpay's SDK reports a user-cancelled checkout via
// PaymentFailureResponse.code == Razorpay.PAYMENT_CANCELLED (2) --
// distinct from a genuine payment failure (other error codes). This is
// what gives us the same success/failure/cancelled three-way split the
// Cashfree wrapper had (Cashfree's own SDK didn't cleanly distinguish
// cancelled from failed -- Razorpay's does).

import 'dart:async';
import 'package:razorpay_flutter/razorpay_flutter.dart';

enum RazorpayResultStatus { success, failure, cancelled }

class RazorpayPaymentResult {
  final RazorpayResultStatus status;
  final String? errorMessage;
  // Populated only on success -- needed if you ever wire the client-side
  // /v1/payment/verify call. NOT required for the recharge/wallet flows
  // as they stand today: those trust the webhook exclusively (see
  // RechargeRouter.kt's Swagger doc comment), so paymentId/signature here
  // are informational only unless a future flow needs them.
  final String? paymentId;
  final String? orderId;
  final String? signature;

  RazorpayPaymentResult({
    required this.status,
    this.errorMessage,
    this.paymentId,
    this.orderId,
    this.signature,
  });
}

class RazorpayService {
  Razorpay? _razorpay;
  Completer<RazorpayPaymentResult>? _completer;

  /// Opens Razorpay's checkout sheet for an order already created on the
  /// backend (which returns razorpayOrderId + razorpayKeyId). Resolves once
  /// the checkout flow completes, errors, or is cancelled -- never throws
  /// for normal payment outcomes, matching CashfreeService.open()'s
  /// contract.
  Future<RazorpayPaymentResult> open({
    required String orderId,
    required String keyId,
    required int amountPaise,
    String name = 'YouPI',
    String description = '',
    String? contactPhone,
    String? contactEmail,
  }) {
    if (keyId.isEmpty || orderId.isEmpty) {
      return Future.value(RazorpayPaymentResult(
        status: RazorpayResultStatus.failure,
        errorMessage: 'Missing orderId or keyId from server.',
      ));
    }

    _completer = Completer<RazorpayPaymentResult>();
    _razorpay = Razorpay();
    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess);
    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _onError);
    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);

    final options = <String, dynamic>{
      'key': keyId,
      'order_id': orderId,
      'amount': amountPaise,
      'name': name,
      'description': description,
      'prefill': {
        if (contactPhone != null && contactPhone.isNotEmpty) 'contact': contactPhone,
        if (contactEmail != null && contactEmail.isNotEmpty) 'email': contactEmail,
      },
    };

    try {
      _razorpay!.open(options);
    } catch (e) {
      if (_completer != null && !_completer!.isCompleted) {
        _completer!.complete(RazorpayPaymentResult(
          status: RazorpayResultStatus.failure,
          errorMessage: e.toString(),
        ));
      }
      _dispose();
    }

    return _completer!.future;
  }

  void _onSuccess(PaymentSuccessResponse response) {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(RazorpayPaymentResult(
        status: RazorpayResultStatus.success,
        paymentId: response.paymentId,
        orderId: response.orderId,
        signature: response.signature,
      ));
    }
    _dispose();
  }

  void _onError(PaymentFailureResponse response) {
    if (_completer != null && !_completer!.isCompleted) {
      final cancelled = response.code == Razorpay.PAYMENT_CANCELLED;
      _completer!.complete(RazorpayPaymentResult(
        status: cancelled ? RazorpayResultStatus.cancelled : RazorpayResultStatus.failure,
        errorMessage: response.message,
      ));
    }
    _dispose();
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    // User picked a wallet (Paytm, etc.) instead of card/UPI/netbanking --
    // Razorpay hands control to that wallet's own flow. Not currently
    // supported by our checkout UX; treat as a soft failure so the caller
    // shows a clear message rather than hanging indefinitely.
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(RazorpayPaymentResult(
        status: RazorpayResultStatus.failure,
        errorMessage: 'External wallet payment (${response.walletName}) is not supported. Please choose UPI, card, or netbanking.',
      ));
    }
    _dispose();
  }

  void _dispose() {
    _razorpay?.clear();
    _razorpay = null;
  }
}