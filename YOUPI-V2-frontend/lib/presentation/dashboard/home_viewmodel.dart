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
  bool _hasLoadedOnce = false;
  String? _error;
  bool _profileLoadFailed = false;
  bool _isGuest = false;

  // Falls back to mock until the real profile loads.
  UserModel _user = MockData.mockUser;
  final List<Map<String, String>> _offers = MockData.mockOffers;

  WalletBalance? _walletBalance;
  List<TransactionModel> _transactions = [];
  List<ActiveRechargeResult> _activeRecharges = [];
  GoldWalletResult? _goldWallet;
  // DEBUG-ONLY -- purely in-memory, never persisted anywhere, never touches
  // the backend. Exists solely so the badge pop-in animation can be
  // previewed while the real gold_wallet table is empty (confirmed via
  // direct DB check -- no recharge has reached RECHARGE_SUCCESS yet, so
  // there's no real data to show). ONLY ever set from the preview-mode
  // branch in emi_selection_screen.dart -- never from the real payment
  // path, so this can never be mistaken for or interfere with real data.
  int? _debugCoinBump;

  bool get isLoading => _isLoading;
  // Only true on the very first load -- used to gate the full-screen
  // shimmer. Was previously shown on EVERY pull-to-refresh too, wiping
  // already-visible content back to a skeleton every time, even though
  // the RefreshIndicator's own spinner already communicates "updating."
  bool get isFirstLoad => _isLoading && !_hasLoadedOnce;
  String? get error => _error;
  bool get isShowingMockProfile => _profileLoadFailed;
  bool get isGuest => _isGuest;
  UserModel get user => _user;
  List<Map<String, String>> get offers => _offers;
  /// All currently-active (non-expired) recharges, soonest-expiring first
  /// -- powers the home screen's horizontally-scrollable Active Recharge
  /// strip. Already FIFO: the backend query excludes anything past its
  /// expiry_date, so an expired recharge simply isn't in this list on the
  /// next load -- no client-side removal/cleanup needed.
  List<ActiveRechargeResult> get activeRecharges => _activeRecharges;

  /// Gold coin count for the home header popup. 0 if not yet loaded / no
  /// rewards earned -- never null, so UI doesn't need extra null checks.
  /// Real backend data now (via GoldRepository), not a local stand-in.
  int get goldCoinCount => _debugCoinBump ?? (_goldWallet?.coinCount ?? 0);

  /// DEBUG-ONLY -- increments the preview-only counter by 1 so you can see
  /// the badge's pop-in animation run repeatedly (1, 2, 3...) without a
  /// real backend credit. Never call this from the real payment path.
  void debugBumpGoldCoinForPreview() {
    _debugCoinBump = (_debugCoinBump ?? (_goldWallet?.coinCount ?? 0)) + 1;
    notifyListeners();
  }

  /// Clears any leftover debug bump from earlier preview testing. Called
  /// on every Home arrival that ISN'T itself a preview bump (see
  /// home_screen.dart) -- without this, testing preview mode once and
  /// then later getting a REAL successful recharge in the same app
  /// session would leave the stale fake number stuck on screen forever,
  /// masking the real backend value. Only an app restart would have
  /// cleared it otherwise.
  void clearDebugCoinBump() {
    if (_debugCoinBump != null) {
      _debugCoinBump = null;
      notifyListeners();
    }
  }

  /// Rupee value of accumulated gold coins.
  double get goldBalanceRupees => _goldWallet?.balanceRupees ?? 0.0;

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
      _activeRecharges = [];
      _goldWallet = null;
      _profileLoadFailed = false;
      _isLoading = false;
      _hasLoadedOnce = true;
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
    _hasLoadedOnce = true;
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
      _activeRecharges = await _rechargeRepo.getActiveRecharges();
    } catch (e) {
      // No active recharges is a normal 200/[] response, not an
      // exception -- this only fires on a genuine network/auth failure,
      // so just fall back to "no active recharge" shown rather than
      // blocking the rest of the home screen.
      debugPrint('Home: active recharge load failed: $e');
      _activeRecharges = [];
    }
  }

  // Gold wallet load failure shouldn't block the rest of the home screen --
  // same isolated-failure pattern as the other _load* methods. Falls back
  // to 0 coins / ₹0 via the getters' null-coalescing.
  Future<void> _loadGoldWallet() async {
    try {
      _goldWallet = await _goldRepo.getWallet();
    } catch (e) {
      debugPrint('Home: gold wallet load failed: $e');
      _goldWallet = null;
    }
  }

  /// Call after a successful withdrawal so the header popup reflects the
  /// new balance without a full home reload.
  void updateGoldWalletAfterWithdraw(GoldWithdrawResult result) {
    _goldWallet = GoldWalletResult(
      coinCount: result.remainingCoinCount,
      balanceRupees: result.remainingBalanceRupees,
    );
    notifyListeners();
  }

  String _cleanError(Object e) =>
      e.toString().replaceFirst('Exception: ', '');
}