import 'package:flutter/material.dart';
import '../../core/services/razorpay_service.dart';
import '../../core/services/storage_service.dart';
import '../../data/models/recharge_plan_model.dart';
import '../../data/repositories/recharge_repository.dart';
import 'recharge_history_screen.dart' show RechargeRecord, RechargeStatus;

enum OperatorDetectionState { idle, detecting, success, failed }

class RechargeViewModel extends ChangeNotifier {
  final RechargeRepository _repo = RechargeRepository();
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
  // NOTE: This calls _repo.getRecentRecharges(...) and _repo.getAllHistory(...)
  // which need to be added to RechargeRepository (see recharge_repository.dart
  // notes below the class). Until those exist on the backend/repo, this will
  // throw and recentRecharges will just stay empty -- the UI already handles
  // that gracefully (section hides itself when the list is empty).
  // ---------------------------------------------------------------------
  // TEMPORARY: Mock data for UI testing (remove once backend history is
  // confirmed working end-to-end). Toggle _useMockHistory to switch back
  // to the real API instantly.
  // ---------------------------------------------------------------------
  static const bool _useMockHistory = true; // TODO: set to false once backend history verified

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
    // NOTE: intentionally NOT gated on `_mobile.length == 10` -- this shows
    // the user's last 4 recharges across ALL numbers they've recharged,
    // not just whatever number happens to be typed in right now. So it
    // loads once on screen open regardless of the mobile field's state.
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
      // leave whatever was previously loaded; RechargeHistoryScreen shows
      // its own empty state if the list stays empty.
    }
  }

  /// Prefills the plan/mobile from a past recharge so the user can quickly
  /// repeat it. Call this before navigating to the plan/EMI selection screen.
  void repeatRecharge(RechargeRecord record) {
    if (record.mobileNumber.length == 10) {
      setMobile(record.mobileNumber);
    }
    // TODO: once RechargeRepository exposes a way to fetch a plan by id/
    // amount+operator, auto-select it here via selectPlan(...). For now the
    // user lands back on the plans list with the correct number & operator
    // pre-filled.
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
    // StorageService.saveLastRechargeMobile(m);
    if (m.length == 10) {
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
    // silent:true -- this reload must NOT flip the screen back to the
    // full-screen shimmer. The user is already looking at the plans list;
    // we just want the underlying data (now for the correct operator) to
    // swap in quietly once it's ready.
    loadPlans(silent: true);
  }

  String? _lastOrderId;
  String? _lastRazorpayOrderId;
  String? get lastOrderId => _lastOrderId;
  String? get lastRazorpayOrderId => _lastRazorpayOrderId;

  bool _paymentInProgress = false;
  bool get paymentInProgress => _paymentInProgress;

  Future<bool> payAndConfirm() async {
    if (_selectedPlan == null) return false;

    if (_mobile.trim().length != 10) {
      _error = 'Please enter a valid 10-digit mobile number.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final order = await _repo.createOrder(
        mobileNumber: _mobile,
        operator: _operator.toUpperCase(),
        circle: _circle,
        planId: _selectedPlan!.id,
        planAmount: _selectedPlan!.price,
        validityDays: _selectedPlan!.validityDays,
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

      _paymentInProgress = true;
      notifyListeners();
      final confirmed = await _pollOrderStatus(order.orderId);
      _rechargeSuccess = confirmed;
      if (!confirmed) {
        _error =
        'Payment received but confirmation is taking longer than usual. '
            'Check My Recharges in a few minutes for the final status.';
      }
      // Refresh recent recharges so the new one shows up next time the
      // user opens this screen / the strip re-renders.
      loadRecentRecharges();
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

  Future<bool> _pollOrderStatus(String orderId) async {
    const maxAttempts = 10;
    const interval = Duration(seconds: 2);
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await Future.delayed(interval);
      try {
        final status = await _repo.getOrderStatus(orderId);
        if (status.isSuccess) return true;
        if (status.isFailed) return false;
      } catch (_) {
        // transient network hiccup while polling -- don't abort early,
        // just try again next tick.
      }
    }
    return false;
  }
}