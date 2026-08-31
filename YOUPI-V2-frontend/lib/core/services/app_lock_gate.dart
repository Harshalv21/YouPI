import 'package:flutter/material.dart';
import '../../routes/app_router.dart';
import 'storage_service.dart';

/// Re-locks the app (MPIN / biometric, GPay/PhonePe style) every time it
/// returns to the foreground after being backgrounded -- ONE time, ONE
/// screen, not stacked.
///
/// Deliberately NOT done via GoRouter's `redirect`: `redirect` only
/// re-runs on navigation, never on an app lifecycle change, so a resume
/// while sitting on (say) /dashboard/home would never trigger it. A
/// WidgetsBindingObserver is the only hook that actually fires on
/// pause/resume.
class AppLockGate extends StatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});

  // Set by MpinEntryScreen while local_auth's own system fingerprint
  // sheet is on screen. IMPORTANT: showing that native sheet itself
  // fires a paused -> resumed pair on Android (it's technically a
  // separate activity/dialog taking focus). Without this guard, the
  // fingerprint prompt closing would itself look like "user left and
  // came back", re-triggering this gate -- which is exactly the
  // MPIN -> reenter MPIN -> fingerprint loop being reported. This flag
  // is what breaks that loop. Lives on the public class (not the
  // private State) since MpinEntryScreen sets it from outside.
  static bool authPromptInProgress = false;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  bool _wasBackgrounded = false;

  static const _skipPrefixes = ['/splash', '/onboarding', '/auth'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (!AppLockGate.authPromptInProgress) _wasBackgrounded = true;
      return;
    }
    if (state == AppLifecycleState.resumed && _wasBackgrounded) {
      _wasBackgrounded = false;
      _maybeLock();
    }
  }

  Future<void> _maybeLock() async {
    // Only lock a real logged-in session that actually has an MPIN set.
    // Guest mode, or mid-registration (no MPIN yet), never gets this.
    final hasToken = await StorageService.hasToken();
    final isGuest = await StorageService.isGuestMode();
    final hasMpin = await StorageService.hasMpin();
    if (!hasToken || isGuest || !hasMpin) return;

    final currentPath = AppRouter.router.routerDelegate.currentConfiguration.uri.path;
    // Already on splash/onboarding/auth (incl. mpin-entry itself, or
    // still mid-registration/mid-KYC) -- don't stack another lock screen.
    if (_skipPrefixes.any((p) => currentPath.startsWith(p))) return;

    AppRouter.router.push('/auth/mpin-entry');
  }

  @override
  Widget build(BuildContext context) => widget.child;
}