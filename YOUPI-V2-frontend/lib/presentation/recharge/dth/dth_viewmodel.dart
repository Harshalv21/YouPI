import 'package:flutter/material.dart';
import '../../../core/services/razorpay_service.dart';
import '../../../core/services/storage_service.dart';
import 'dth_operator_model.dart';
import 'dth_repository.dart';

enum _DthPollOutcome { success, failed, unknown }

class DthViewModel extends ChangeNotifier {
  final DthRepository _repo = DthRepository();
  final RazorpayService _razorpayService = RazorpayService();

  bool _isLoadingOperators = false;
  List<DthOperatorModel> _operators = [];
  DthOperatorModel? _selectedOperator;
  String _subscriberNumber = '';
  double? _amount;

  String _paymentMode = 'FULL'; // FULL or WALLET -- DTH doesn't support SPLIT/EMI
  bool _isLoading = false;
  bool _paymentInProgress = false;
  String? _error;
  bool _rechargeSuccess = false;
  bool _stillProcessing = false;

  bool _isFetchingCustomerInfo = false;
  DthCustomerInfo? _customerInfo;
  String? _customerInfoError;

  bool _isLoadingRecents = false;
  List<DthRecentAccount> _recentAccounts = [];

  bool get isLoadingOperators => _isLoadingOperators;
  List<DthOperatorModel> get operators => _operators;
  DthOperatorModel? get selectedOperator => _selectedOperator;
  String get subscriberNumber => _subscriberNumber;
  double? get amount => _amount;
  String get paymentMode => _paymentMode;
  bool get isLoading => _isLoading;
  bool get paymentInProgress => _paymentInProgress;
  String? get error => _error;
  bool get rechargeSuccess => _rechargeSuccess;
  bool get stillProcessing => _stillProcessing;

  bool get isFetchingCustomerInfo => _isFetchingCustomerInfo;
  DthCustomerInfo? get customerInfo => _customerInfo;
  String? get customerInfoError => _customerInfoError;

  bool get isLoadingRecents => _isLoadingRecents;
  List<DthRecentAccount> get recentAccounts => _recentAccounts;

  Future<void> loadOperators() async {
    _isLoadingOperators = true;
    notifyListeners();
    try {
      _operators = await _repo.getOperators();
    } finally {
      _isLoadingOperators = false;
      notifyListeners();
    }
  }

  /// Powers the "Recents" section on DthOperatorSelectScreen. Fails soft
  /// (see DthRepository.getRecentAccounts()) -- an empty list on error just
  /// means the section doesn't render, never a blocked screen.
  Future<void> loadRecentAccounts() async {
    _isLoadingRecents = true;
    notifyListeners();
    try {
      _recentAccounts = await _repo.getRecentAccounts();
    } finally {
      _isLoadingRecents = false;
      notifyListeners();
    }
  }

  void selectOperator(DthOperatorModel operator) {
    _selectedOperator = operator;
    notifyListeners();
  }

  void setSubscriberNumber(String value) {
    _subscriberNumber = value.trim();
    notifyListeners();
  }

  void setAmount(double value) {
    _amount = value;
    notifyListeners();
  }

  void selectFullPayment() {
    _paymentMode = 'FULL';
    notifyListeners();
  }

  void selectWalletPayment() {
    _paymentMode = 'WALLET';
    notifyListeners();
  }

  // Resets state when the flow is re-entered (dashboard -> DTH -> back ->
  // DTH again) -- same reasoning as RechargeHomeScreen clearing _mobileCtrl
  // on init, so a stale operator/subscriberId from a previous visit doesn't
  // silently carry over.
  void reset() {
    _selectedOperator = null;
    _subscriberNumber = '';
    _amount = null;
    _paymentMode = 'FULL';
    _error = null;
    _rechargeSuccess = false;
    _stillProcessing = false;
    _isFetchingCustomerInfo = false;
    _customerInfo = null;
    _customerInfoError = null;
    notifyListeners();
  }

  /// Looks up the subscriber via mPlan (DthRouter's GET /dth/customer-info)
  /// as soon as the subscriber ID is confirmed -- so a mistyped ID or a
  /// non-existent/never-activated account surfaces right there, before the
  /// user ever reaches the amount screen, instead of only showing up as a
  /// payment failure later. On success, pre-fills _amount from mPlan's
  /// MonthlyRecharge so DthAmountScreen opens with the bill amount already
  /// populated (still editable) -- matches the "enter subscriber ID once,
  /// see name + amount auto-filled" flow. Returns true only when a valid
  /// customer record came back; DthCustomerIdScreen uses the return value
  /// to decide whether to navigate on to /dth/amount or show the error
  /// inline instead.
  Future<bool> fetchCustomerInfo() async {
    if (_selectedOperator == null || _subscriberNumber.isEmpty) return false;

    _isFetchingCustomerInfo = true;
    _customerInfoError = null;
    _customerInfo = null;
    notifyListeners();

    try {
      final info = await _repo.getCustomerInfoByVc(
        vcNumber: _subscriberNumber,
        operator: _selectedOperator!.name,
      );
      _customerInfo = info;
      if (info.monthlyRecharge != null && info.monthlyRecharge! > 0) {
        _amount = info.monthlyRecharge;
      }
      return true;
    } catch (e) {
      // e.toString() surfaces the backend's actual message (e.g. "Subscriber
      // not found Invalid Customer ID" from mPlan) -- same pattern as the
      // generic catch in payAndConfirm() below.
      _customerInfoError = e.toString();
      return false;
    } finally {
      _isFetchingCustomerInfo = false;
      notifyListeners();
    }
  }

  Future<bool> payAndConfirm() async {
    if (_selectedOperator == null) {
      _error = 'Please select a DTH operator.';
      notifyListeners();
      return false;
    }
    if (_subscriberNumber.isEmpty) {
      _error = 'Please enter your subscriber ID.';
      notifyListeners();
      return false;
    }
    if (_amount == null || _amount! <= 0) {
      _error = 'Please enter a valid amount.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    _stillProcessing = false;
    notifyListeners();

    try {
      final order = await _repo.createOrder(
        subscriberNumber: _subscriberNumber,
        operator: _selectedOperator!.name,
        amount: _amount!,
        paymentMode: _paymentMode,
        idempotencyKey: '$_subscriberNumber-${_selectedOperator!.name}-${DateTime.now().millisecondsSinceEpoch}',
      );

      // ── WALLET branch -- synchronous, same as mobile recharge: backend
      // already debited + attempted A1Topup delivery by the time
      // createOrder() returns.
      if (_paymentMode == 'WALLET') {
        final status = order.status?.toUpperCase();
        if (status == 'RECHARGE_SUCCESS' || status == 'SUCCESS') {
          _rechargeSuccess = true;
        } else if (status == 'RECHARGE_FAILED' || status == 'FAILED') {
          _rechargeSuccess = false;
          _error = 'Your recharge failed. If your wallet was debited, the amount will be refunded automatically within 24-48 hours.';
        } else {
          _rechargeSuccess = false;
          _stillProcessing = true;
          _error = 'Your recharge is being confirmed. Check My Recharges in a few minutes for the final status.';
        }
        return _rechargeSuccess;
      }

      if (order.razorpayOrderId == null || order.razorpayOrderId!.isEmpty) {
        _error = 'Could not start payment. Please try again.';
        return false;
      }
      if (order.razorpayKeyId == null || order.razorpayKeyId!.isEmpty) {
        _error = 'Could not start payment. Please try again.';
        return false;
      }

      _isLoading = false;
      notifyListeners();

      final ownMobile = await StorageService.getLastMobile();

      final rzResult = await _razorpayService.open(
        orderId: order.razorpayOrderId!,
        keyId: order.razorpayKeyId!,
        amountPaise: (_amount! * 100).round(),
        description: 'DTH recharge for $_subscriberNumber',
        contactPhone: ownMobile,
      );

      if (rzResult.status == RazorpayResultStatus.cancelled) {
        _rechargeSuccess = false;
        return false;
      }
      if (rzResult.status == RazorpayResultStatus.failure) {
        _error = rzResult.errorMessage ?? 'Payment failed. Please try again.';
        _rechargeSuccess = false;
        return false;
      }

      _paymentInProgress = true;
      notifyListeners();
      final outcome = await _pollOrderStatus(order.orderId);
      switch (outcome) {
        case _DthPollOutcome.success:
          _rechargeSuccess = true;
          _stillProcessing = false;
          break;
        case _DthPollOutcome.failed:
          _rechargeSuccess = false;
          _stillProcessing = false;
          _error = 'Payment was received but the recharge failed. '
              'Any amount deducted will be refunded within 3-5 business days.';
          break;
        case _DthPollOutcome.unknown:
          _rechargeSuccess = false;
          _stillProcessing = true;
          _error = 'Payment received but confirmation is taking longer than usual. '
              'Check My Recharges in a few minutes for the final status.';
          break;
      }
      return _rechargeSuccess;
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

  Future<_DthPollOutcome> _pollOrderStatus(String orderId) async {
    const maxAttempts = 25;
    const interval = Duration(seconds: 2);
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await Future.delayed(interval);
      try {
        final status = await _repo.getOrderStatus(orderId);
        if (status.isSuccess) return _DthPollOutcome.success;
        if (status.isFailed) return _DthPollOutcome.failed;
      } catch (_) {
        // transient network hiccup while polling -- try again next tick
      }
    }
    return _DthPollOutcome.unknown;
  }
}