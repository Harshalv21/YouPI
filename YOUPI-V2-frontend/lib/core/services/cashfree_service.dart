// lib/core/services/cashfree_service.dart
//
// Thin async/await wrapper around flutter_cashfree_pg_sdk's callback-based
// API, mirroring RazorpayService's shape so recharge_viewmodel.dart's
// payAndConfirm() can branch cleanly between the two.
//
// Uses the "PG Web Checkout" flow (CFWebCheckoutPaymentBuilder) -- this
// matches what our backend already provides (order_id + payment_session_id
// from a plain order-create call), no card-vault/native-card-widget setup
// needed on this side.
//
// API surface confirmed against flutter_cashfree_pg_sdk's own official
// example app (5-6 Aug 2026) -- not guessed.
//
// SECURITY NOTE (same as RazorpayService): the SDK's success callback
// (verifyPayment) means ONLY "the checkout flow completed and needs
// verification" -- it is explicitly named "verify", not "success", in
// Cashfree's own sample. It does NOT mean the recharge was granted. The
// caller MUST still poll the backend's order-status endpoint and wait for
// Cashfree's webhook to confirm server-side -- exactly like the existing
// Razorpay flow. Do not shortcut that here.
//
// OPEN QUESTION (flagged, not guessed): Cashfree's sample doesn't show a
// distinct "user cancelled" signal separate from onError -- unlike
// Razorpay's response.code == 2 check. If a QA pass shows the SDK calling
// onError specifically when the user backs out of the sheet (vs. a real
// payment failure), the error message/CFErrorResponse contents at that
// point should be inspected to see if they can be told apart. Until then,
// this treats all onError calls as CashfreeResultStatus.failure -- slightly
// less precise than the Razorpay path's cancelled/failure split, but never
// incorrectly reports success.

import 'package:flutter_cashfree_pg_sdk/api/cfpaymentgateway/cfpaymentgatewayservice.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfsession/cfsession.dart';
import 'package:flutter_cashfree_pg_sdk/api/cfpayment/cfwebcheckoutpayment.dart';
import 'package:flutter_cashfree_pg_sdk/api/cferrorresponse/cferrorresponse.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfenums.dart';
import 'package:flutter_cashfree_pg_sdk/utils/cfexceptions.dart';
import 'dart:async';

enum CashfreeResultStatus { success, failure, cancelled }

class CashfreePaymentResult {
  final CashfreeResultStatus status;
  final String? errorMessage;

  CashfreePaymentResult({required this.status, this.errorMessage});
}

class CashfreeService {
  /// "SANDBOX" during testing / phased rollout, "PRODUCTION" only after
  /// full cutover -- MUST be kept in sync with the backend's
  /// youpi.cashfree.environment. Passed at build time same pattern as
  /// RAZORPAY_KEY_ID:
  ///   flutter run --dart-define=CASHFREE_ENV=SANDBOX
  static const String _envString = String.fromEnvironment(
    'CASHFREE_ENV',
    defaultValue: 'SANDBOX',
  );

  CFEnvironment get _environment =>
      _envString.toUpperCase() == 'PRODUCTION' ? CFEnvironment.PRODUCTION : CFEnvironment.SANDBOX;

  final _cfPaymentGatewayService = CFPaymentGatewayService();
  Completer<CashfreePaymentResult>? _completer;

  /// Opens Cashfree's hosted web-checkout for an order already created on
  /// the backend (which returns both razorpayOrderId -- Cashfree's actual
  /// order_id, despite the field name -- and paymentSessionId). Resolves
  /// once the checkout flow completes (verify), errors, or is cancelled --
  /// never throws for normal payment outcomes, matching
  /// RazorpayService.open()'s contract.
  Future<CashfreePaymentResult> open({
    required String orderId,
    required String paymentSessionId,
  }) {
    if (paymentSessionId.isEmpty || orderId.isEmpty) {
      return Future.value(CashfreePaymentResult(
        status: CashfreeResultStatus.failure,
        errorMessage: 'Missing orderId or paymentSessionId from server.',
      ));
    }

    _completer = Completer<CashfreePaymentResult>();
    _cfPaymentGatewayService.setCallback(_onVerify, _onError);

    try {
      final session = CFSessionBuilder()
          .setEnvironment(_environment)
          .setOrderId(orderId)
          .setPaymentSessionId(paymentSessionId)
          .build();

      final cfWebCheckout = CFWebCheckoutPaymentBuilder().setSession(session).build();
      _cfPaymentGatewayService.doPayment(cfWebCheckout);
    } on CFException catch (e) {
      _completer!.complete(CashfreePaymentResult(
        status: CashfreeResultStatus.failure,
        errorMessage: e.message,
      ));
    }

    return _completer!.future;
  }

  void _onVerify(String orderId) {
    // Named "verify" (not "success") in Cashfree's own SDK -- this is a
    // signal to go verify server-side, not a confirmed success. Same
    // caller-must-poll contract as Razorpay's success callback.
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(CashfreePaymentResult(status: CashfreeResultStatus.success));
    }
  }

  void _onError(CFErrorResponse errorResponse, String orderId) {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(CashfreePaymentResult(
        status: CashfreeResultStatus.failure,
        errorMessage: errorResponse.getMessage(),
      ));
    }
  }
}