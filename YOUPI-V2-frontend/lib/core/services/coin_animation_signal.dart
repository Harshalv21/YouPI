// lib/core/services/coin_animation_signal.dart
//
// A minimal broadcast signal connecting push_notification_service.dart to
// home_screen.dart's ALREADY-BUILT _checkPendingCoinAnimation() mechanism,
// without duplicating its logic (toast state, animation trigger, etc.) in
// a second place.
//
// Why this exists: home_screen.dart only runs its pending-animation check
// in initState(). That's enough when a push arrives while the app is
// closed/backgrounded (navigating to Home creates a fresh HomeScreen,
// initState runs naturally). But if the user is ALREADY sitting on Home
// in the foreground when the push arrives, navigating to the same route
// again does NOT re-trigger initState() -- GoRouter reuses the existing
// widget/state. This signal lets push_notification_service.dart say
// "something changed, please recheck" to whichever HomeScreen instance
// is currently listening, covering that case too.
import 'package:flutter/foundation.dart';

class CoinAnimationSignal {
  static final ValueNotifier<int> tick = ValueNotifier(0);
  static void fire() => tick.value++;
}