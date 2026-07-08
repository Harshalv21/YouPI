import 'package:flutter/material.dart';
import '../../data/datasources/mock_data.dart';
import '../../data/models/user_model.dart';
import '../../data/models/transaction_model.dart';
import '../../data/models/wallet_model.dart';
import '../../data/repositories/wallet_repository.dart';
import '../../data/repositories/user_repository.dart';

class HomeViewModel extends ChangeNotifier {
  final WalletRepository _walletRepo = WalletRepository();
  final UserRepository _userRepo = UserRepository();

  bool _isLoading = false;
  String? _error;

  // Falls back to mock until the real profile loads.
  UserModel _user = MockData.mockUser;
  final List<Map<String, String>> _offers = MockData.mockOffers;

  WalletBalance? _walletBalance;
  List<TransactionModel> _transactions = [];

  bool get isLoading => _isLoading;
  String? get error => _error;
  UserModel get user => _user;
  List<Map<String, String>> get offers => _offers;

  /// Primary spendable balance (NBFC wallet).
  double get walletBalance =>
      _walletBalance?.nbfcBalance ?? _user.walletBalance;

  List<WalletInfo> get wallets => _walletBalance?.wallets ?? [];

  List<TransactionModel> get recentTransactions => _transactions.isNotEmpty
      ? _transactions.take(4).toList()
      : MockData.mockTransactions.take(4).toList();

  Future<void> loadHome() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    // Load profile, balance and ledger in parallel. Each is isolated so
    // one failure doesn't blank the whole screen.
    await Future.wait([
      _loadProfile(),
      _loadBalance(),
      _loadTransactions(),
    ]);

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadProfile() async {
    try {
      _user = await _userRepo.getProfile();
    } catch (e) {
      debugPrint('Home: profile load failed: $e');
    }
  }

  Future<void> _loadBalance() async {
    try {
      _walletBalance = await _walletRepo.getBalance();
    } catch (e) {
      _error = _cleanError(e);
    }
  }

  Future<void> _loadTransactions() async {
    try {
      _transactions = await _walletRepo.getLedger(type: 'NBFC', page: 0);
    } catch (e) {
      debugPrint('Home: ledger load failed: $e');
    }
  }

  String _cleanError(Object e) =>
      e.toString().replaceFirst('Exception: ', '');
}