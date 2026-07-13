import 'package:flutter/material.dart';
import '../../data/datasources/mock_data.dart';
import '../../data/models/gold_model.dart';
import '../../data/models/loan_model.dart';
import '../../data/models/transaction_model.dart';
import '../../data/repositories/invest_repository.dart';
import '../../data/repositories/wallet_repository.dart';

class InvestViewModel extends ChangeNotifier {
  final InvestRepository _repo = InvestRepository();
  bool _isLoading = false;
  String? _error;
  GoldModel _gold = MockData.mockGold;
  double _buyAmount = 500;
  double _fdAmount = 10000;
  int _fdMonths = 12;
  double _fdRate = 7.5;
  bool _isGoldBuy = true;
  bool _transactionSuccess = false;

  bool get isLoading => _isLoading;
  String? get error => _error;
  GoldModel get gold => _gold;
  double get buyAmount => _buyAmount;
  double get fdAmount => _fdAmount;
  int get fdMonths => _fdMonths;
  double get fdRate => _fdRate;
  bool get isGoldBuy => _isGoldBuy;
  bool get transactionSuccess => _transactionSuccess;
  double get gramsForBuyAmount =>
      _buyAmount / (_isGoldBuy ? _gold.pricePerGram : _gold.sellRatePerGram);
  double get fdMaturity => FdModel.calculateMaturity(_fdAmount, _fdRate, _fdMonths);
  double get interestEarned => fdMaturity - _fdAmount;

  void setIsGoldBuy(bool v) { _isGoldBuy = v; notifyListeners(); }
  void setBuyAmount(double v) { _buyAmount = v; notifyListeners(); }
  void setFdAmount(double v) { _fdAmount = v; notifyListeners(); }
  void setFdMonths(int v) { _fdMonths = v; notifyListeners(); }
  void setFdRate(double v) { _fdRate = v; notifyListeners(); }

  Future<void> ensureAugmontUser({required String name, required String email, required String mobile}) =>
      _repo.ensureAugmontUser(name: name, email: email, mobile: mobile);

  Future<void> loadGold() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final price = await _repo.getGoldPrice();
      _gold = await _repo.getGoldHoldings(price);
    } catch (e) {
      // Keep whatever we had (mock fallback on first load) rather than
      // blanking the screen -- but don't hide the failure either, a caller
      // may want to show a small inline notice via vm.error.
      _error = 'Could not refresh live gold price. Pull to retry.';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<bool> transactGold() async {
    _isLoading = true;
    notifyListeners();
    bool ok;
    try {
      if (_isGoldBuy) {
        ok = await _repo.buyGold(_buyAmount);
      } else {
        ok = await _repo.sellGold(gramsForBuyAmount);
      }
    } catch (_) {
      ok = false;
    }
    _transactionSuccess = ok;
    if (ok) {
      // Optimistic local update for instant feedback -- loadGold() (called
      // again by the screen after a successful transact) will overwrite
      // this with the real server-confirmed balance right after.
      _gold = _gold.copyWith(
        balanceGrams: _gold.balanceGrams + (isGoldBuy ? gramsForBuyAmount : -gramsForBuyAmount),
        balanceValue: _gold.balanceValue + (isGoldBuy ? buyAmount : -buyAmount),
      );
    }
    _isLoading = false;
    notifyListeners();
    return ok;
  }

// Note: "Open FD Now" is intentionally locked (ComingSoonOverlay) in
// fd_calculator_screen.dart and never calls into the ViewModel -- there's
// no real cash-based FD creation endpoint on the backend to call (only
// weight-based Gold FD exists, see invest_repository.dart header). No
// openFd() method here on purpose; add one back only once a real
// create-FD call exists to wire it to.
}

class WalletViewModel extends ChangeNotifier {
  final WalletRepository _repo = WalletRepository();

  bool _isLoading = false;
  String? _error;
  double _balance = 0;
  List<TransactionModel> _transactions = [];

  bool get isLoading => _isLoading;
  String? get error => _error;
  double get balance => _balance;
  List<TransactionModel> get transactions => _transactions;

  Future<void> loadWallet() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _repo.getNbfcBalance(),
        _repo.getLedger(type: 'NBFC'),
      ]);
      _balance = results[0] as double;
      _transactions = results[1] as List<TransactionModel>;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}