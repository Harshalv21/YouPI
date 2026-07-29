import 'package:flutter/material.dart';
import '../../data/datasources/mock_data.dart';
import '../../data/models/user_model.dart';
import '../../data/models/transaction_model.dart';
import '../../data/models/wallet_model.dart';
import '../../data/repositories/wallet_repository.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/repositories/recharge_repository.dart';
import '../../data/repositories/gold_repository.dart';    
import '../../core/services/storage_service.dart';

class HomeViewModel extends ChangeNotifier {
  final WalletRepository _walletRepo = WalletRepository();
  final UserRepository _userRepo = UserRepository();
  final RechargeRepository _rechargeRepo = RechargeRepository();
  final GoldRepository _goldRepo = GoldRepository();     

  bool _isLoading = false;
  String? _error;
  bool _profileLoadFailed = false;
  bool _isGuest = false;

  // Falls back to mock until the real profile loads.
  UserModel _user = MockData.mockUser;
  final List<Map<String, String>> _offers = MockData.mockOffers;

  WalletBalance? _walletBalance;
  List<TransactionModel> _transactions = [];
  ActiveRechargeResult? _activeRecharge;
  GoldWalletResult? _goldWallet;         

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isShowingMockProfile => _profileLoadFailed;
  bool get isGuest => _isGuest;
  UserModel get user => _user;
  List<Map<String, String>> get offers => _offers;
  ActiveRechargeResult? get activeRecharge => _activeRecharge;

  /// Gold coin count for the home header popup. 0 if not yet loaded / no
  /// rewards earned -- never null, so UI doesn't need extra null checks.
  int get goldCoinCount => _goldWallet?.coinCount ?? 0;          // ← ADD

  /// Rupee value of accumulated gold coins.
  double get goldBalanceRupees => _goldWallet?.balanceRupees ?? 0.0;  // ← ADD

  /// Primary spendable balance (NBFC wallet).
  double get walletBalance =>
      _walletBalance?.nbfcBalance ?? _user.walletBalance;

  List<WalletInfo> get wallets => _walletBalance?.wallets ?? [];

  List<TransactionModel> get recentTransactions => _transactions.isNotEmpty
      ? _transactions.take(4).toList()
      : MockData.mockTransactions.take(4).toList();

  static const _guestUser = UserModel(
    id: '',
    name: 'Guest',
    mobile: '',
    email: '',
    kycStatus: 'pending',
  );

  Future<void> loadHome() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final isGuest = await StorageService.isGuestMode();
    _isGuest = isGuest;

    if (isGuest) {
      // Guests have no token -- every one of these calls would just 401.
      // Previously this fell through to _loadProfile()'s catch block, which
      // only set a "failed" flag and left whatever user data (real or mock)
      // was already cached from a *previous* logged-in session still on
      // screen -- so a guest could see a stale "Welcome back, <real name>"
      // greeting. Reset to an explicit, clean guest state instead of ever
      // calling these endpoints.
      _user = _guestUser;
      _walletBalance = null;
      _transactions = [];
      _activeRecharge = null;
      _goldWallet = null;     
      _profileLoadFailed = false;
      _isLoading = false;
      notifyListeners();
      return;
    }

    // Load profile, balance and ledger in parallel. Each is isolated so
    // one failure doesn't blank the whole screen.
    await Future.wait([
      _loadProfile(),
      _loadBalance(),
      _loadTransactions(),
      _loadActiveRecharge(),
      _loadGoldWallet(),   
    ]);

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadProfile() async {
    try {
      _user = await _userRepo.getProfile();
    } catch (e) {
      // Was completely silent before -- falls back to mock data with zero
      // visible trace of why. Now logs loudly so "why is it showing mock
      // data" has an answer in the console instead of being a mystery.
      debugPrint('🔴 Home: profile load failed, showing MOCK data instead: $e');
      _profileLoadFailed = true;
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

  Future<void> _loadActiveRecharge() async {
    try {
      _activeRecharge = await _rechargeRepo.getActiveRecharge();
    } catch (e) {
      // No active recharge is a normal 200/null response, not an
      // exception -- this only fires on a genuine network/auth failure,
      // so just fall back to "no active recharge" shown rather than
      // blocking the rest of the home screen.
      debugPrint('Home: active recharge load failed: $e');
      _activeRecharge = null;
    }
  }

   // Gold wallet load failure shouldn't block the rest of the home screen --
  // same isolated-failure pattern as the other _load* methods. Falls back
  // to 0 coins / ₹0 via the getters' null-coalescing.
  Future<void> _loadGoldWallet() async {                        // ← ADD
    try {
      _goldWallet = await _goldRepo.getWallet();
    } catch (e) {
      debugPrint('Home: gold wallet load failed: $e');
      _goldWallet = null;
    }
  }

  /// Call after a successful withdrawal so the header popup reflects the
  /// new balance without a full home reload.
  void updateGoldWalletAfterWithdraw(GoldWithdrawResult result) {  // ← ADD
    _goldWallet = GoldWalletResult(
      coinCount: result.remainingCoinCount,
      balanceRupees: result.remainingBalanceRupees,
    );
    notifyListeners();
  }

  String _cleanError(Object e) =>
      e.toString().replaceFirst('Exception: ', '');
}