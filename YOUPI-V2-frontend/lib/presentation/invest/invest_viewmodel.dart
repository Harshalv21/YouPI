import 'package:flutter/material.dart';
import '../../data/datasources/mock_data.dart';
import '../../data/models/gold_model.dart';
import '../../data/models/loan_model.dart';
import '../../data/repositories/invest_repository.dart';

class InvestViewModel extends ChangeNotifier {
  final InvestRepository _repo = InvestRepository();
  bool _isLoading = false;
  GoldModel _gold = MockData.mockGold;
  double _buyAmount = 500;
  double _fdAmount = 10000;
  int _fdMonths = 12;
  double _fdRate = 7.5;
  bool _isGoldBuy = true;
  bool _transactionSuccess = false;

  bool get isLoading => _isLoading;
  GoldModel get gold => _gold;
  double get buyAmount => _buyAmount;
  double get fdAmount => _fdAmount;
  int get fdMonths => _fdMonths;
  double get fdRate => _fdRate;
  bool get isGoldBuy => _isGoldBuy;
  bool get transactionSuccess => _transactionSuccess;
  double get gramsForBuyAmount => _buyAmount / _gold.pricePerGram;
  double get fdMaturity => FdModel.calculateMaturity(_fdAmount, _fdRate, _fdMonths);
  double get interestEarned => fdMaturity - _fdAmount;

  void setIsGoldBuy(bool v) { _isGoldBuy = v; notifyListeners(); }
  void setBuyAmount(double v) { _buyAmount = v; notifyListeners(); }
  void setFdAmount(double v) { _fdAmount = v; notifyListeners(); }
  void setFdMonths(int v) { _fdMonths = v; notifyListeners(); }
  void setFdRate(double v) { _fdRate = v; notifyListeners(); }

  Future<void> loadGold() async {
    _isLoading = true;
    notifyListeners();
    _gold = await _repo.getGoldPrice();
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> transactGold() async {
    _isLoading = true;
    notifyListeners();
    bool ok;
    if (_isGoldBuy) {
      ok = await _repo.buyGold(_buyAmount);
    } else {
      ok = await _repo.sellGold(gramsForBuyAmount);
    }
    _transactionSuccess = ok;
    if (ok) {
      _gold = _gold.copyWith(
        balanceGrams: _gold.balanceGrams + (isGoldBuy ? gramsForBuyAmount : -gramsForBuyAmount),
        balanceValue: _gold.balanceValue + (isGoldBuy ? buyAmount : -buyAmount),
      );
    }
    _isLoading = false;
    notifyListeners();
    return ok;
  }

  Future<bool> openFd() async {
    _isLoading = true;
    notifyListeners();
    final ok = await _repo.openFd(_fdAmount, _fdMonths);
    _transactionSuccess = ok;
    _isLoading = false;
    notifyListeners();
    return ok;
  }
}

class WalletViewModel extends ChangeNotifier {
  bool _isLoading = false;
  double _balance = MockData.mockUser.walletBalance;

  bool get isLoading => _isLoading;
  double get balance => _balance;
  List get transactions => MockData.mockTransactions;

  Future<void> loadWallet() async {
    _isLoading = true; notifyListeners();
    await Future.delayed(const Duration(milliseconds: 500));
    _isLoading = false; notifyListeners();
  }
}
