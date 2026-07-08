import 'package:flutter/material.dart';
import '../../data/datasources/mock_data.dart';
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
    notifyListeners();
    try {
      _plans = await _repo.getPlans();
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

  Future<bool> confirmRecharge() async {
    if (_selectedPlan == null) return false;
    _isLoading = true;
    notifyListeners();
    try {
      final ok = await _repo.processRecharge(
        mobile: _mobile,
        plan: _selectedPlan!,
        emiOption: _selectedEmi,
      );
      _rechargeSuccess = ok;
      return ok;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
