import 'package:flutter/material.dart';
import '../../core/services/razorpay_service.dart';
import '../../core/services/storage_service.dart';
import '../../data/models/recharge_plan_model.dart';
import '../../data/repositories/recharge_repository.dart';

class RechargeViewModel extends ChangeNotifier {
  final RechargeRepository _repo = RechargeRepository();
  final RazorpayService _razorpayService = RazorpayService();

  bool _isLoading = false;
  String? _error;
  List<RechargePlanModel> _plans = [];
  RechargePlanModel? _selectedPlan;
  EmiOption? _selectedEmi;
  // Empty by default -- was a hardcoded '9876543210' before, which looked
  // like a real, already-filled-in number and confused users into thinking
  // someone's actual number was pre-selected. Empty lets the UI show a
  // proper placeholder (GPay-style) instead, and the recharge screen
  // prompts the user to pick a number/contact before proceeding.
  String _mobile = '';
  String _operator = 'airtel';
  String _circle = 'UP East';
  String _searchQuery = '';
  List<String> _activeFilters = [];
  bool _rechargeSuccess = false;

  // Recharge-target number is otherwise pure in-memory state -- when the
  // OS reclaims memory after the app is backgrounded/switched away from
  // (common on lower-RAM devices), Flutter can recreate the widget tree
  // and this viewmodel from scratch, silently losing whatever the user
  // had typed. Persisting to StorageService (same mechanism already used
  // for the logged-in user's own last-used mobile) survives that.
  RechargeViewModel() {
    _restoreLastRechargeMobile();
  }

  Future<void> _restoreLastRechargeMobile() async {
    final saved = await StorageService.getLastRechargeMobile();
    if (saved != null && saved.length == 10) {
      _mobile = saved;
      notifyListeners();
    }
  }

  bool get isLoading => _isLoading;
  String? get error => _error;
  List<RechargePlanModel> get plans => _plans;
  RechargePlanModel? get selectedPlan => _selectedPlan;
  EmiOption? get selectedEmi => _selectedEmi;
  String get mobile => _mobile;
  String get operator => _operator;
  String get circle => _circle;
  bool get rechargeSuccess => _rechargeSuccess;

  List<RechargePlanModel> get filteredPlans {
    var filtered = _plans;
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((p) =>
      p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.price.toString().contains(_searchQuery) ||
          p.dataPerDay.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }
    return filtered;
  }

  Future<void> loadPlans() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _plans = await _repo.getPlans(operator: _operator.toUpperCase(), circle: _circle);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void selectPlan(RechargePlanModel plan) {
    _selectedPlan = plan;
    _selectedEmi = plan.emiOptions.isNotEmpty ? plan.emiOptions.first : null;
    notifyListeners();
  }

  void selectEmi(EmiOption emi) {
    _selectedEmi = emi;
    notifyListeners();
  }

  /// Switches to "pay in full, no EMI" -- backend derives paymentMode as
  /// FULL whenever _selectedEmi is null (see payAndConfirm below).
  void selectFullPayment() {
    _selectedEmi = null;
    notifyListeners();
  }

  void setSearchQuery(String q) {
    _searchQuery = q;
    notifyListeners();
  }

  void setMobile(String m) {
    _mobile = m;
    StorageService.saveLastRechargeMobile(m);
    notifyListeners();
  }

  String? _lastOrderId;
  String? _lastRazorpayOrderId;
  String? get lastOrderId => _lastOrderId;
  String? get lastRazorpayOrderId => _lastRazorpayOrderId;

  // Distinct from _isLoading -- used by the UI to know we're specifically
  // waiting on the Razorpay sheet / post-payment confirmation poll, not a
  // plain network call, so it can show a different message ("Confirming
  // your payment...") instead of a generic spinner.
  bool _paymentInProgress = false;
  bool get paymentInProgress => _paymentInProgress;

  /// Full real-payment flow:
  ///  1. Create the order on the backend (status INITIATED).
  ///  2. Open Razorpay's native Checkout sheet for that order.
  ///  3. Regardless of what the Checkout sheet itself reports, poll the
  ///     backend's READ-ONLY status endpoint and wait for the Razorpay
  ///     webhook to actually confirm the order server-side.
  ///
  /// Step 3 is not optional. The client-side Checkout callback is not
  /// trusted for anything -- that's the exact vulnerability that was fixed
  /// on the backend (see RechargeService.handleWebhookCaptured). Only the
  /// server-to-server webhook can move an order past INITIATED.
  Future<bool> payAndConfirm() async {
    if (_selectedPlan == null) return false;

    // Guard against the now-empty default mobile -- previously a fake
    // '9876543210' silently sailed through to order creation. Now we
    // actually stop and tell the user, instead of creating an order for
    // an empty/invalid number.
    if (_mobile.trim().length != 10) {
      _error = 'Please enter a valid 10-digit mobile number.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Step 1 -- create order
      final order = await _repo.createOrder(
        mobileNumber: _mobile,
        operator: _operator.toUpperCase(),
        circle: _circle,
        planId: _selectedPlan!.id,
        planAmount: _selectedPlan!.price,
        paymentMode: _selectedEmi == null
            ? 'FULL'
            : 'EMI_${_selectedEmi!.months}',
        idempotencyKey: '${_mobile}-${_selectedPlan!.id}-${DateTime.now().millisecondsSinceEpoch}',
      );
      _lastOrderId = order.orderId;
      _lastRazorpayOrderId = order.razorpayOrderId;

      if (order.razorpayOrderId.isEmpty) {
        _error = 'Could not start payment. Please try again.';
        return false;
      }

      // Step 2 -- open Checkout. Prefill with the LOGGED-IN user's own
      // contact (for the receipt), not the recharge target's mobile --
      // those can be different numbers (recharging someone else).
      _isLoading = false;
      notifyListeners();

      final ownMobile = await StorageService.getLastMobile();

      final result = await _razorpayService.open(
        razorpayOrderId: order.razorpayOrderId,
        amountRupees: order.amount,
        name: 'YouPI Recharge',
        description:
        '${_selectedPlan!.operator.toUpperCase()} ₹${_selectedPlan!.price.toStringAsFixed(0)}',
        contactPhone: ownMobile,
      );

      if (result.status == RazorpayResultStatus.cancelled) {
        _error = 'Payment cancelled.';
        _rechargeSuccess = false;
        return false;
      }
      if (result.status == RazorpayResultStatus.failure) {
        _error = result.errorMessage ?? 'Payment failed. Please try again.';
        _rechargeSuccess = false;
        return false;
      }

      // Step 3 -- wait for the webhook, not the client callback.
      _paymentInProgress = true;
      notifyListeners();
      final confirmed = await _pollOrderStatus(order.orderId);
      _rechargeSuccess = confirmed;
      if (!confirmed) {
        _error =
        'Payment received but confirmation is taking longer than usual. '
            'Check My Recharges in a few minutes for the final status.';
      }
      return confirmed;
    } catch (e) {
      _error = e.toString();
      _rechargeSuccess = false;
      return false;
    } finally {
      _isLoading = false;
      _paymentInProgress = false;
      notifyListeners();
    }
  }

  /// Polls the read-only order-status endpoint every 2s, up to ~20s,
  /// waiting for the Razorpay webhook to land server-side.
  /// Returns true only for a genuinely confirmed order (PAYMENT_DONE /
  /// RECHARGE_SUCCESS); false for RECHARGE_FAILED or timeout (still
  /// INITIATED -- caller should tell the user to check history later,
  /// since the webhook may still land after this poll gives up).
  Future<bool> _pollOrderStatus(String orderId) async {
    const maxAttempts = 10;
    const interval = Duration(seconds: 2);
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await Future.delayed(interval);
      try {
        final status = await _repo.getOrderStatus(orderId);
        if (status.isSuccess) return true;
        if (status.isFailed) return false;
        // still INITIATED -- keep polling
      } catch (_) {
        // transient network hiccup while polling -- don't abort early,
        // just try again next tick.
      }
    }
    return false;
  }
}