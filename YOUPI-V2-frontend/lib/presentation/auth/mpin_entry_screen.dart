// TODO Implement this library.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/app_lock_gate.dart';

/// App-open lock screen. Shown on every launch when the user is logged in
/// and has an MPIN set. Verifies against the locally stored MPIN hash.
///
/// Two modes, chosen once at open based on the user's saved preference:
/// - Biometric ON  -> `_LockMode.biometric`: fingerprint-first screen with
///   an explicit "Verify using passcode" fallback and a close button to
///   exit the app. Never silently drops into the PIN pad on its own.
/// - Biometric OFF -> `_LockMode.pin`: straight to the MPIN pad, no
///   fingerprint UI shown at all.
///
/// On success → /dashboard/home.
/// After 5 wrong MPIN attempts → temporarily blocks input.
class MpinEntryScreen extends StatefulWidget {
  const MpinEntryScreen({super.key});

  @override
  State<MpinEntryScreen> createState() => _MpinEntryScreenState();
}

enum _LockMode { loading, biometric, pin }

class _MpinEntryScreenState extends State<MpinEntryScreen> {
  static const int _maxAttempts = 5;

  final LocalAuthentication _localAuth = LocalAuthentication();

  _LockMode _mode = _LockMode.loading;
  String _mpin = '';
  int _attempts = 0;
  bool _isLocked = false;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final enabled = await StorageService.isBiometricEnabled();
    if (!mounted) return;
    if (enabled) {
      setState(() => _mode = _LockMode.biometric);
      // Offer the native prompt right away once the biometric screen is
      // showing -- user can also retap the fingerprint icon to retry.
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
    } else {
      // Biometric off -> passcode only. No fingerprint UI, no auto prompt.
      setState(() => _mode = _LockMode.pin);
    }
  }

  void _switchToPasscode() {
    setState(() => _mode = _LockMode.pin);
  }

  void _exitApp() {
    // Lock screen has no "back" destination inside the app -- closing it
    // should close the app, same as GPay/PhonePe's X on their lock screen.
    SystemNavigator.pop();
  }

  Future<void> _tryBiometric() async {
    final enabled = await StorageService.isBiometricEnabled();
    if (!enabled) {
      debugPrint('Biometric: skipped -- not enabled in settings (StorageService.isBiometricEnabled() == false)');
      return;
    }
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) {
        debugPrint('Biometric: device reports canCheckBiometrics == false');
        return;
      }
      // Tell AppLockGate a native biometric sheet is about to take over
      // the screen. On Android that transition itself fires a
      // paused -> resumed pair, which -- without this flag -- AppLockGate
      // would read as "user backgrounded the app and came back", pushing
      // ANOTHER mpin-entry screen on top and reopening biometric again.
      // That loop is exactly the "MPIN -> reenter MPIN -> fingerprint"
      // behaviour that was previously reported.
      AppLockGate.authPromptInProgress = true;
      bool ok = false;
      try {
        ok = await _localAuth.authenticate(
          localizedReason: 'Unlock YOUPI',
          options: const AuthenticationOptions(
            biometricOnly: true,
            stickyAuth: true,
          ),
        );
      } finally {
        AppLockGate.authPromptInProgress = false;
      }
      debugPrint('Biometric: authenticate() returned $ok');
      if (ok && mounted) {
        context.go('/dashboard/home');
      }
      // Failed/cancelled -> stay on the biometric screen. User explicitly
      // taps "Verify using passcode" to switch, we never auto-switch.
    } catch (e) {
      AppLockGate.authPromptInProgress = false;
      // BUG FIX: this was previously `catch (_) {}` -- completely silent,
      // including the most likely real cause (missing native Android
      // setup: MainActivity must extend FlutterFragmentActivity, and
      // AndroidManifest.xml needs the USE_BIOMETRIC permission). If that
      // native config is wrong, local_auth throws here on every attempt.
      // Logging it is the only way to actually diagnose it.
      debugPrint('Biometric: authenticate() threw -- $e');
    }
  }

  void _onDigit(String d) {
    if (_isLocked || _checking) return;
    if (_mpin.length >= 4) return;
    setState(() {
      _mpin += d;
      if (_mpin.length == 4) _verify();
    });
  }

  void _onDelete() {
    if (_isLocked || _checking) return;
    if (_mpin.isEmpty) return;
    setState(() => _mpin = _mpin.substring(0, _mpin.length - 1));
  }

  Future<void> _verify() async {
    setState(() => _checking = true);
    final ok = await StorageService.verifyMpin(_mpin);

    if (ok) {
      if (mounted) context.go('/dashboard/home');
      return;
    }

    // Wrong MPIN
    _attempts++;
    setState(() {
      _mpin = '';
      _checking = false;
    });

    if (_attempts >= _maxAttempts) {
      setState(() => _isLocked = true);
      _showError(
          'Too many wrong attempts. Please sign in again with OTP.');
      // Force re-login: clear session and send to welcome.
      await StorageService.clearAll();
      if (mounted) context.go('/onboarding/welcome');
      return;
    }

    _showError(
        'Wrong MPIN. ${_maxAttempts - _attempts} attempt(s) left.');
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  Future<void> _forgotMpin() async {
    // Forgot MPIN → re-authenticate via OTP. Clear session, go to login.
    await StorageService.clearAll();
    if (mounted) context.go('/auth/mobile');
  }

  @override
  Widget build(BuildContext context) {
    // Lock screen has nothing to pop back to (splash/onboarding sit below
    // it in the stack, but going "back" into those doesn't make sense
    // here). System back button and the X button both do the exact same
    // thing: exit to the background via SystemNavigator.pop(), same as
    // pressing Home -- the app stays alive and shows up in the Recents
    // switcher, it just isn't force-closed or killed.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _exitApp();
      },
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    switch (_mode) {
      case _LockMode.loading:
        return const Scaffold(
          backgroundColor: AppColors.backgroundPrimary,
          body: SizedBox.shrink(),
        );
      case _LockMode.biometric:
        return _buildBiometricScreen();
      case _LockMode.pin:
        return _buildPinScreen();
    }
  }

  // ── Biometric screen (shown only when biometric is enabled) ──

  Widget _buildBiometricScreen() {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimensions.paddingPage),
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  onPressed: _exitApp,
                  tooltip: 'Exit app',
                  icon: const Icon(Icons.close_rounded, color: AppColors.textPrimary),
                ),
              ),
              const Spacer(),
              Text('Verify with fingerprint',
                  style: AppTextStyles.displaySmall,
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('Use your fingerprint to unlock YouPI',
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: _switchToPasscode,
                style: OutlinedButton.styleFrom(
                  shape: const StadiumBorder(),
                  side: const BorderSide(color: AppColors.divider),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
                child: Text('Verify using passcode', style: AppTextStyles.bodyMedium),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _tryBiometric,
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.primary),
                  ),
                  child: const Icon(Icons.fingerprint_rounded,
                      color: AppColors.primary, size: 44),
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  // ── Passcode (MPIN) screen ──

  Widget _buildPinScreen() {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      // BUG FIX: this screen used to be Padding(child: Column(...with a
      // Spacer()...)) directly in SafeArea -- no scroll fallback at all.
      // Spacer() demands the Column's remaining space add up to >= 0; on
      // a short device, with a large system font-scale setting, or with
      // the number pad's fixed 80x72 keys simply not fitting under the
      // header + dots + "Forgot MPIN?" link, that assumption breaks and
      // Flutter throws "RenderFlex overflowed by N pixels" at the bottom
      // (the yellow/black striped error banner). LayoutBuilder +
      // SingleChildScrollView + ConstrainedBox(minHeight) + IntrinsicHeight
      // is the standard fix for a Spacer-based layout that should still
      // center/spread its content when everything fits, but become
      // scrollable instead of overflowing when it doesn't.
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppDimensions.paddingPage),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - (AppDimensions.paddingPage * 2),
                ),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const SizedBox(height: 40),
                      // Lock icon
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primary),
                        ),
                        child: const Icon(Icons.lock_rounded,
                            color: AppColors.primary, size: 30),
                      ),
                      const SizedBox(height: 20),
                      Text('Enter MPIN',
                          style: AppTextStyles.displaySmall,
                          textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      Text('Enter your 4-digit MPIN to continue',
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.textSecondary),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 40),
                      // Dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                            4,
                                (i) => Container(
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i < _mpin.length
                                    ? AppColors.primary
                                    : AppColors.divider,
                                boxShadow: i < _mpin.length
                                    ? [
                                  BoxShadow(
                                      color: AppColors.primaryGlow,
                                      blurRadius: 8)
                                ]
                                    : null,
                              ),
                            )),
                      ),
                      const SizedBox(height: 16),
                      if (_checking)
                        const CircularProgressIndicator(color: AppColors.primary),
                      const Spacer(),
                      // Number pad
                      for (final row in [
                        ['1', '2', '3'],
                        ['4', '5', '6'],
                        ['7', '8', '9'],
                        ['', '0', '⌫']
                      ])
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: row.map((d) {
                            return GestureDetector(
                              onTap: () {
                                if (d == '⌫') {
                                  _onDelete();
                                } else if (d.isEmpty) {
                                  // No-op placeholder key -- fingerprint
                                  // key removed from this pad: biometric
                                  // now only appears on its own screen
                                  // (_buildBiometricScreen), never mixed
                                  // into the passcode pad.
                                } else {
                                  _onDigit(d);
                                }
                              },
                              child: Container(
                                width: 80,
                                height: 72,
                                margin: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: d.isEmpty
                                      ? Colors.transparent
                                      : AppColors.backgroundCard,
                                  borderRadius: BorderRadius.circular(12),
                                  border: d.isEmpty
                                      ? null
                                      : Border.all(color: AppColors.divider),
                                ),
                                child: Center(
                                  child: d == '⌫'
                                      ? const Icon(Icons.backspace_rounded,
                                      color: AppColors.textSecondary, size: 20)
                                      : Text(d,
                                      style: AppTextStyles.headlineLarge),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _forgotMpin,
                        child: Text('Forgot MPIN?', style: AppTextStyles.tealLink),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}