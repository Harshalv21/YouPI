// lib/core/services/razorpay_service.dart
//
// Thin async/await wrapper around `razorpay_flutter`'s callback-based API.
//
// IMPORTANT — SECURITY: The result returned here (`success`) means ONLY
// "the Razorpay sheet closed reporting success" — it does NOT mean the
// recharge has been granted. The backend already had a real fraud
// vulnerability where a client-reported success was trusted directly (see
// RechargeService.handleWebhookCaptured fix). DO NOT repeat that mistake
// here: after this returns success, the caller MUST poll the backend's
// read-only order-status endpoint and wait for the Razorpay webhook to
// actually confirm the order server-side before treating anything as paid.

import 'dart:async';
import 'package:razorpay_flutter/razorpay_flutter.dart';

enum RazorpayResultStatus { success, failure, cancelled }

class RazorpayPaymentResult {
  final RazorpayResultStatus status;
  final String? paymentId;
  final String? errorMessage;

  RazorpayPaymentResult({
    required this.status,
    this.paymentId,
    this.errorMessage,
  });
}

class RazorpayService {
  /// Public/publishable key ID — safe to embed client-side (NOT the
  /// secret, that lives only in the backend's Secret Manager).
  /// MUST be passed at build/run time:
  ///   flutter run --dart-define=RAZORPAY_KEY_ID=rzp_live_xxxxxxxx
  static const String keyId = String.fromEnvironment(
    'RAZORPAY_KEY_ID',
    defaultValue: '',
  );

  Razorpay? _razorpay;
  Completer<RazorpayPaymentResult>? _completer;

  /// Opens Razorpay's native Checkout sheet for an order already created
  /// on the backend. Resolves once the sheet closes (success, error, or
  /// user-cancel) — never throws for normal payment outcomes.
  Future<RazorpayPaymentResult> open({
    required String razorpayOrderId,
    required double amountRupees,
    required String name,
    String? description,
    String? contactPhone,
    String? contactEmail,
  }) {
    if (keyId.isEmpty) {
      return Future.value(RazorpayPaymentResult(
        status: RazorpayResultStatus.failure,
        errorMessage:
        'RAZORPAY_KEY_ID not configured. Build with --dart-define=RAZORPAY_KEY_ID=rzp_xxx',
      ));
    }

    _completer = Completer<RazorpayPaymentResult>();
    _razorpay = Razorpay();
    _razorpay!.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onSuccess);
    _razorpay!.on(Razorpay.EVENT_PAYMENT_ERROR, _onError);
    _razorpay!.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);

    final options = <String, dynamic>{
      'key': keyId,
      'order_id': razorpayOrderId,
      // Display-only on the sheet. The authoritative amount lives on the
      // order created server-side against `razorpayOrderId` — Razorpay
      // enforces that, this field can't be used to pay a different amount.
      'amount': (amountRupees * 100).round(), // paise
      'name': name,
      if (description != null) 'description': description,
      'prefill': {
        if (contactPhone != null && contactPhone.isNotEmpty) 'contact': contactPhone,
        if (contactEmail != null && contactEmail.isNotEmpty) 'email': contactEmail,
      },
      'theme': {'color': '#000000'},
    };

    try {
      _razorpay!.open(options);
    } catch (e) {
      _completer!.complete(RazorpayPaymentResult(
        status: RazorpayResultStatus.failure,
        errorMessage: e.toString(),
      ));
    }

    return _completer!.future.whenComplete(_dispose);
  }

  void _onSuccess(PaymentSuccessResponse response) {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(RazorpayPaymentResult(
        status: RazorpayResultStatus.success,
        paymentId: response.paymentId,
      ));
    }
  }

  void _onError(PaymentFailureResponse response) {
    if (_completer != null && !_completer!.isCompleted) {
      // Razorpay error code 2 == user closed the sheet (cancelled), not a
      // real payment failure. Keep these distinct so the UI can message
      // "cancelled" vs "failed" correctly instead of scaring the user.
      final cancelled = response.code == 2;
      _completer!.complete(RazorpayPaymentResult(
        status: cancelled ? RazorpayResultStatus.cancelled : RazorpayResultStatus.failure,
        errorMessage: response.message,
      ));
    }
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    // User picked an external wallet (Paytm etc) mid-flow — not a final
    // outcome yet, Razorpay still fires success/error afterward. No-op.
  }

  void _dispose() {
    _razorpay?.clear();
    _razorpay = null;
  }
}