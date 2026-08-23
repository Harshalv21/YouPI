import 'package:flutter/material.dart';
// import '../../core/services/cashfree_service.dart';
import '../../core/services/api_service.dart';
import '../../core/services/razorpay_service.dart';
import '../../core/services/storage_service.dart';
import '../../data/models/recharge_plan_model.dart';
import '../../data/repositories/recharge_repository.dart';
import 'recharge_history_screen.dart' show RechargeRecord, RechargeStatus;

enum OperatorDetectionState { idle, detecting, success, failed }

class RechargeViewModel extends ChangeNotifier {
  final RechargeRepository _repo = RechargeRepository();
  // final CashfreeService _cashfreeService = CashfreeService();
  final RazorpayService _razorpayService = RazorpayService();

  bool _isLoading = false;
  bool _isPlansRefreshing = false;
  String? _error;
  List<RechargePlanModel> _plans = [];
  RechargePlanModel? _selectedPlan;
  EmiOption? _selectedEmi;
  String _mobile = '';
  String _operator = 'airtel';
  String _circle = 'UP East';
  OperatorDetectionState _detectionState = OperatorDetectionState.idle;
  String _searchQuery = '';
  List<String> _activeFilters = [];
  bool _rechargeSuccess = false;
  // true when the PAYMENT itself succeeded but the recharge fulfillment
  // (A1Topup) didn't confirm within the polling window -- distinct from a
  // genuine failure (cancelled/rejected payment). The caller should show a
  // "still processing" message and let the user continue, not an error.
  bool _stillProcessing = false;

  // ── Payment mode (Wallet + SPLIT support) ──
  String _paymentMode = 'FULL'; // FULL or WALLET or SPLIT
  double? _walletShortfall;
  double? _walletBalance;

  // ← NAYA: SPLIT mode ke liye -- kitna wallet se use karna hai (consent
  // screen se set hota hai), aur order create hone ke baad backend se
  // mila actual breakdown.
  double? _splitWalletAmount;
  double? _orderWalletAmount;
  double? _orderGatewayAmount;

  String get paymentMode => _paymentMode;
  double? get walletShortfall => _walletShortfall;
  double? get walletBalance => _walletBalance;
  double? get splitWalletAmount => _splitWalletAmount;
  double? get orderWalletAmount => _orderWalletAmount;
  double? get orderGatewayAmount => _orderGatewayAmount;

  // ---- Recharge history state (NEW) ----
  List<RechargeRecord> _recentRecharges = [];
  List<RechargeRecord> _allRechargeHistory = [];
  bool _isLoadingRecent = false;

  RechargeViewModel() {
    // _restoreLastRechargeMobile();
  }

  // Future<void> _restoreLastRechargeMobile() async {
  //   final saved = await StorageService.getLastRechargeMobile();
  //   if (saved != null && saved.length == 10) {
  //     _mobile = saved;
  //     notifyListeners();
  //   }
  // }

  // isLoading -- true only for the very first plans load (screen just
  // opened, nothing on screen yet). Drives the full-screen ShimmerList.
  bool get isLoading => _isLoading;
  // isPlansRefreshing -- true when plans are being silently reloaded
  // in the background (e.g. after operator detection changes the
  // operator/circle). The rest of the screen (mobile number, dialog,
  // scroll position) stays exactly as-is; only used for a small,
  // optional inline indicator on the plans section itself, not a
  // full-screen swap.
  bool get isPlansRefreshing => _isPlansRefreshing;
  String? get error => _error;
  List<RechargePlanModel> get plans => _plans;
  RechargePlanModel? get selectedPlan => _selectedPlan;
  EmiOption? get selectedEmi => _selectedEmi;
  String get mobile => _mobile;
  String get operator => _operator;
  String get circle => _circle;
  OperatorDetectionState get detectionState => _detectionState;
  bool get rechargeSuccess => _rechargeSuccess;
  bool get stillProcessing => _stillProcessing;

  // ---- Recharge history getters (NEW) ----
  List<RechargeRecord> get recentRecharges => _recentRecharges;
  List<RechargeRecord> get allRechargeHistory => _allRechargeHistory;
  bool get isLoadingRecent => _isLoadingRecent;

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

  /// [silent] -- when true (used for refreshes triggered by operator
  /// detection), only _isPlansRefreshing toggles, so the screen doesn't
  /// flash back to the full-screen shimmer/reload state. The very first
  /// call (from initState, plans list still empty) should NOT pass
  /// silent:true, so the user still sees the shimmer instead of a blank
  /// screen while the initial plans load.
  Future<void> loadPlans({bool silent = false}) async {
    if (silent) {
      _isPlansRefreshing = true;
    } else {
      _isLoading = true;
    }
    _error = null;
    notifyListeners();
    try {
      _plans = await _repo.getPlans(operator: _operator.toUpperCase(), circle: _circle);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      _isPlansRefreshing = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------
  // Recharge history (NEW)
  // ---------------------------------------------------------------------
  static const bool _useMockHistory = false; // now using real backend history

  List<RechargeRecord> _mockHistory() {
    final now = DateTime.now();
    return [
      RechargeRecord(
        id: 'mock1',
        mobileNumber: '8104842621',
        operator: 'JIO',
        circle: 'Mumbai',
        amount: 249,
        planDescription: '2GB/day, 28 Days, Unlimited Calls',
        validity: '28 Days',
        paymentMethod: 'Razorpay',
        paymentTxnId: 'pay_MOCK0001',
        status: RechargeStatus.success,
        goldCoinsEarned: 25,
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      RechargeRecord(
        id: 'mock2',
        mobileNumber: '9876543210',
        operator: 'AIRTEL',
        circle: 'UP East',
        amount: 49,
        planDescription: 'Unlimited Data Add-on',
        validity: '1 Day',
        paymentMethod: 'Razorpay',
        paymentTxnId: 'pay_MOCK0002',
        status: RechargeStatus.failed,
        failureReason: 'Operator declined the request. Amount will be refunded in 3-5 business days.',
        createdAt: now.subtract(const Duration(hours: 6)),
      ),
      RechargeRecord(
        id: 'mock3',
        mobileNumber: '8104842621',
        operator: 'JIO',
        circle: 'Mumbai',
        amount: 33,
        planDescription: '2GB Data, Validity 2 Days',
        validity: '2 Days',
        paymentMethod: 'Razorpay',
        paymentTxnId: 'pay_MOCK0003',
        status: RechargeStatus.success,
        goldCoinsEarned: 3,
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      RechargeRecord(
        id: 'mock4',
        mobileNumber: '7009988776',
        operator: 'VI',
        circle: 'Delhi',
        amount: 179,
        planDescription: '1.5GB/day, 24 Days',
        validity: '24 Days',
        paymentMethod: 'Razorpay',
        paymentTxnId: 'pay_MOCK0004',
        status: RechargeStatus.pending,
        createdAt: now.subtract(const Duration(minutes: 20)),
      ),
      RechargeRecord(
        id: 'mock5',
        mobileNumber: '8104842621',
        operator: 'JIO',
        circle: 'Mumbai',
        amount: 48,
        planDescription: '6GB Data, Validity 3 Days',
        validity: '3 Days',
        paymentMethod: 'Razorpay',
        paymentTxnId: 'pay_MOCK0005',
        status: RechargeStatus.failed,
        failureReason: 'Payment failed at gateway. No amount was deducted.',
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      RechargeRecord(
        id: 'mock6',
        mobileNumber: '9123456780',
        operator: 'BSNL',
        circle: 'Kerala',
        amount: 299,
        planDescription: '3GB/day, 84 Days',
        validity: '84 Days',
        paymentMethod: 'Razorpay',
        paymentTxnId: 'pay_MOCK0006',
        status: RechargeStatus.success,
        goldCoinsEarned: 30,
        createdAt: now.subtract(const Duration(days: 3)),
      ),
      RechargeRecord(
        id: 'mock7',
        mobileNumber: '9876543210',
        operator: 'AIRTEL',
        circle: 'UP East',
        amount: 99,
        planDescription: 'Talktime Top-up',
        validity: 'N/A',
        paymentMethod: 'Razorpay',
        paymentTxnId: 'pay_MOCK0007',
        status: RechargeStatus.success,
        goldCoinsEarned: 10,
        createdAt: now.subtract(const Duration(days: 5)),
      ),
    ];
  }
  // ---------------------------------------------------------------------

  Future<void> loadRecentRecharges() async {
    _isLoadingRecent = true;
    notifyListeners();
    try {
      if (_useMockHistory) {
        await Future.delayed(const Duration(milliseconds: 300)); // simulate network
        _recentRecharges = _mockHistory().take(4).toList();
      } else {
        _recentRecharges = await _repo.getRecentRecharges(limit: 4);
      }
    } catch (e) {
      _recentRecharges = [];
    } finally {
      _isLoadingRecent = false;
      notifyListeners();
    }
  }

  Future<void> hideRecentRecharge(String orderId) async {
    await _repo.hideFromHistory([orderId]);
    await loadRecentRecharges(); // refresh list after hiding
  }

  Future<void> loadAllRechargeHistory() async {
    try {
      if (_useMockHistory) {
        await Future.delayed(const Duration(milliseconds: 300));
        _allRechargeHistory = _mockHistory();
      } else {
        _allRechargeHistory = await _repo.getAllRechargeHistory();
      }
      notifyListeners();
    } catch (e) {
      debugPrint('loadAllRechargeHistory failed: $e'); // TEMP -- remove once diagnosed
    }
  }

  /// Prefills the plan/mobile from a past recharge so the user can quickly
  /// repeat it. Call this before navigating to the plan/EMI selection screen.
  void repeatRecharge(RechargeRecord record) {
    if (record.mobileNumber.length == 10) {
      setMobile(record.mobileNumber);
    }
  }

  void selectPlan(RechargePlanModel plan) {
    _selectedPlan = plan;
    _selectedEmi = plan.emiOptions.isNotEmpty ? plan.emiOptions.first : null;
    notifyListeners();
  }

  void setOperatorAndCircle(String operator, String circle) {
    _operator = operator.toLowerCase();
    _circle = circle;
    _detectionState = OperatorDetectionState.success;
    notifyListeners();
  }

  void selectEmi(EmiOption emi) {
    _selectedEmi = emi;
    notifyListeners();
  }

  void selectFullPayment() {
    _paymentMode = 'FULL';
    _selectedEmi = null;
    notifyListeners();
  }

  // ← wallet-as-payment-method ke liye
  void selectWalletPayment() {
    _paymentMode = 'WALLET';
    _selectedEmi = null;
    notifyListeners();
  }

  // ← NAYA: wallet + gateway combination ke liye
  void selectSplitPayment() {
    _paymentMode = 'SPLIT';
    _selectedEmi = null;
    notifyListeners();
  }

  // ← NAYA: SPLIT mode mein wallet se kitna use karna hai, ye set karta hai
  void setSplitWalletAmount(double amount) {
    _splitWalletAmount = amount;
    notifyListeners();
  }

  void setSearchQuery(String q) {
    _searchQuery = q;
    notifyListeners();
  }

  void setMobile(String m, {bool autoDetectOperator = true}) {
    _mobile = m;
    // StorageService.saveLastRechargeMobile(m);
    if (autoDetectOperator && m.length == 10) {
      _detectOperator(m);
    } else {
      _detectionState = OperatorDetectionState.idle;
      notifyListeners();
    }
    notifyListeners();
  }

  Future<void> _detectOperator(String mobileNumber) async {
    _detectionState = OperatorDetectionState.detecting;
    notifyListeners();

    try {
      final result = await _repo.detectOperator(mobileNumber);
      if (_mobile != mobileNumber) return;
      _operator = result.operator.toLowerCase();
      _circle = result.circle;
      _detectionState = OperatorDetectionState.success;
    } catch (e) {
      if (_mobile != mobileNumber) return;
      _detectionState = OperatorDetectionState.failed;
    }
    notifyListeners();
    loadPlans(silent: true);
  }

  String? _lastOrderId;
  String? _lastRazorpayOrderId;
  String? get lastOrderId => _lastOrderId;
  String? get lastRazorpayOrderId => _lastRazorpayOrderId;

  bool _paymentInProgress = false;
  bool get paymentInProgress => _paymentInProgress;

  // ← Backend ke jitne bhi "success" ke liye status string ho sakte hai
  // unhe ek jagah normalize kiya hai. WALLET branch pehle SIRF
  // 'RECHARGE_SUCCESS' se match karta tha -- agar backend kabhi
  // 'SUCCESS' ya 'COMPLETED' ya lowercase bheje, to _rechargeSuccess
  // silently false ban jaata tha aur UI pe na success screen aata tha
  // na error -- bilkul kuch nahi hota tha. Ye set match ko robust
  // banata hai.
  static const Set<String> _walletSuccessStatuses = {
    'RECHARGE_SUCCESS',
    'SUCCESS',
    'COMPLETED',
    'RECHARGE_COMPLETED',
  };

  // ← NAYA: genuine failure ko "still processing" se alag pehchanna zaroori
  // hai -- warna operator-decline jaisa clear failure bhi "confirm ho raha
  // hai, thoda ruko" jaisa misleading message dikhata rahega.
  static const Set<String> _walletFailureStatuses = {
    'RECHARGE_FAILED',
    'FAILED',
    'REJECTED',
    'CANCELLED',
    'DECLINED',
  };

  bool _isWalletOrderSuccessful(String? status) {
    if (status == null) return false;
    return _walletSuccessStatuses.contains(status.toUpperCase());
  }

  bool _isWalletOrderFailed(String? status) {
    if (status == null) return false;
    return _walletFailureStatuses.contains(status.toUpperCase());
  }

  Future<bool> payAndConfirm() async {
    if (_selectedPlan == null) return false;

    if (_mobile.trim().length != 10) {
      _error = 'Please enter a valid 10-digit mobile number.';
      notifyListeners();
      return false;
    }

    if (_detectionState == OperatorDetectionState.failed) {
      _error = 'Could not confirm the operator for this number. Please pick it manually and try again.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    _stillProcessing = false;
    _walletShortfall = null;
    _walletBalance = null;
    notifyListeners();

    try {
      final order = await _repo.createOrder(
        mobileNumber: _mobile,
        operator: _operator.toUpperCase(),
        circle: _circle,
        planId: _selectedPlan!.id,
        planAmount: _selectedPlan!.price,
        validityDays: _selectedPlan!.validityDays,
        paymentMode: _paymentMode == 'WALLET'
            ? 'WALLET'
            : (_paymentMode == 'SPLIT'
                ? 'SPLIT'
                : (_selectedEmi == null ? 'FULL' : 'EMI_${_selectedEmi!.months}')),
        idempotencyKey: '${_mobile}-${_selectedPlan!.id}-${DateTime.now().millisecondsSinceEpoch}',
        walletAmount: _paymentMode == 'SPLIT' ? _splitWalletAmount : null,
      );
      _lastOrderId = order.orderId;
      _lastRazorpayOrderId = order.razorpayOrderId;
      // ← NAYA: SPLIT breakdown backend se store kar lo (consent UI ke liye)
      _orderWalletAmount = order.walletAmount;
      _orderGatewayAmount = order.gatewayAmount;

      // ── WALLET branch -- synchronous, no Razorpay checkout at all ──
      // Backend already debited + attempted A1Topup delivery by the time
      // createOrder() returns (see RechargeService.createWalletPaidOrder()).
      if (_paymentMode == 'WALLET') {
        // TEMP debug -- confirms the exact status string backend sends
        // for WALLET orders. Remove once verified in production logs.
        debugPrint('[WALLET] order.status = "${order.status}" orderId=${order.orderId}');

        if (_isWalletOrderSuccessful(order.status)) {
          _rechargeSuccess = true;
        } else if (_isWalletOrderFailed(order.status)) {
          // ← Genuine failure -- e.g. operator declined the recharge after
          // wallet was already debited. Don't say "still processing" here,
          // that would mislead the user into thinking it just needs time.
          _rechargeSuccess = false;
          _stillProcessing = false;
          _error = 'Your recharge failed. If your wallet was debited, the amount will be refunded automatically within 24-48 hours.';
        } else {
          // Status string we don't recognize yet -- genuinely unclear,
          // not a confirmed failure. Treat as processing so the user
          // gets pointed to My Recharges instead of a silent no-op.
          _rechargeSuccess = false;
          _stillProcessing = true;
          _error = 'Your recharge is being confirmed. Check My Recharges in a few minutes for the final status.';
        }
        loadRecentRecharges();
        return _rechargeSuccess;
      }

      if (order.razorpayOrderId.isEmpty) {
        _error = 'Could not start payment. Please try again.';
        return false;
      }

      _isLoading = false;
      notifyListeners();

      final ownMobile = await StorageService.getLastMobile();

      if (order.razorpayKeyId == null || order.razorpayKeyId!.isEmpty) {
        _error = 'Could not start payment. Please try again.';
        _rechargeSuccess = false;
        return false;
      }

      // ← NAYA: SPLIT mode mein Razorpay ko sirf gateway-portion bhejna hai,
      // poora plan price nahi. FULL/EMI mode mein pehle jaisa behaviour hi.
      final gatewayPayableAmount = (_paymentMode == 'SPLIT' && order.gatewayAmount != null)
          ? order.gatewayAmount!
          : _selectedPlan!.price;

      final rzResult = await _razorpayService.open(
        orderId: order.razorpayOrderId,
        keyId: order.razorpayKeyId!,
        amountPaise: (gatewayPayableAmount * 100).round(),
        description: 'Recharge for $_mobile',
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
        case _PollOutcome.success:
          _rechargeSuccess = true;
          _stillProcessing = false;
          break;
        case _PollOutcome.failed:
          // ← Genuine failure after payment succeeded -- e.g. operator
          // declined the recharge. Clear error, not a "processing" message,
          // since that would wrongly suggest the user should just wait.
          _rechargeSuccess = false;
          _stillProcessing = false;
          _error = 'Payment was received but the recharge failed. '
              'Any amount deducted will be refunded within 3-5 business days.';
          break;
        case _PollOutcome.unknown:
          _rechargeSuccess = false;
          _stillProcessing = true;
          _error =
          'Payment received but confirmation is taking longer than usual. '
              'Check My Recharges in a few minutes for the final status.';
          await StorageService.setPendingCoinAnimation(order.orderId, _selectedPlan!.price);
          break;
      }
      loadRecentRecharges();
      return _rechargeSuccess;
    } catch (e) {
      // ← wallet insufficient-balance case -- pull structured
      // details out so UI can show exact shortfall + "Add Money" CTA.
      if (e is ApiException && e.code == 'WALLET_PAYMENT_REJECTED') {
        _walletBalance = (e.details?['walletBalance'] as num?)?.toDouble();
        _walletShortfall = (e.details?['shortfall'] as num?)?.toDouble();
      }
      _error = e.toString();
      _rechargeSuccess = false;
      return false;
    } finally {
      _isLoading = false;
      _paymentInProgress = false;
      notifyListeners();
    }
  }

  // ← Tri-state instead of bool: polling ka "no" do alag matlab ho sakte
  // hai -- backend ne explicitly FAILED bola (genuine failure), ya
  // max attempts khatam ho gaye bina kisi clear jawab ke (genuinely
  // unclear/still processing). Pehle dono ko same "stillProcessing"
  // treat kiya jaata tha jo failure ke case mein misleading tha.
  Future<_PollOutcome> _pollOrderStatus(String orderId) async {
    const maxAttempts = 25;
    const interval = Duration(seconds: 2);
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await Future.delayed(interval);
      try {
        final status = await _repo.getOrderStatus(orderId);
        if (status.isSuccess) return _PollOutcome.success;
        if (status.isFailed) return _PollOutcome.failed;
      } catch (_) {
        // transient network hiccup while polling -- don't abort early,
        // just try again next tick.
      }
    }
    return _PollOutcome.unknown;
  }
}

enum _PollOutcome { success, failed, unknown }