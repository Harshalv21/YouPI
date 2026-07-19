import 'package:flutter/material.dart';
import '../../data/models/recharge_plan_model.dart';
import '../../data/repositories/recharge_repository.dart';

class RechargeViewModel extends ChangeNotifier {
  final RechargeRepository _repo = RechargeRepository();

  bool _isLoading = false;
  String? _error;
  List<RechargePlanModel> _plans = [];
  RechargePlanModel? _selectedPlan;
  EmiOption? _selectedEmi;
  String _mobile = '9876543210';
  String _operator = 'airtel';
  String _circle = 'UP East';
  String _searchQuery = '';
  List<String> _activeFilters = [];
  bool _rechargeSuccess = false;

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

  void setSearchQuery(String q) {
    _searchQuery = q;
    notifyListeners();
  }

  void setMobile(String m) {
    _mobile = m;
    notifyListeners();
  }

  String? _lastOrderId;
  String? _lastRazorpayOrderId;
  String? get lastOrderId => _lastOrderId;
  String? get lastRazorpayOrderId => _lastRazorpayOrderId;

  Future<bool> confirmRecharge() async {
    if (_selectedPlan == null) return false;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _repo.createOrder(
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
      _lastOrderId = result.orderId;
      _lastRazorpayOrderId = result.razorpayOrderId;
      // NOTE: order is created on the backend at this point (status
      // INITIATED), but no payment has actually been collected --
      // razorpay_flutter isn't wired into this screen (or anywhere in the
      // app) yet. `_rechargeSuccess = true` here reflects "order placed",
      // matching the previous mock's meaning, NOT "money charged" or
      // "recharge delivered". Real completion only happens via the
      // Razorpay webhook once Checkout is integrated -- see
      // RechargeRepository.createOrder doc comment.
      _rechargeSuccess = true;
      return true;
    } catch (e) {
      _error = e.toString();
      _rechargeSuccess = false;
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}