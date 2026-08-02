// lib/core/services/push_notification_service.dart
//
// FCM push notification handling -- specifically built to close the last
// gap in the recharge-success reward animation flow:
//
//   1. emi_selection_screen.dart polls synchronously for ~50s right after
//      payment (recharge_viewmodel.dart's _pollOrderStatus).
//   2. If that times out, home_screen.dart's _checkPendingCoinAnimation
//      re-checks for ~75s more, but ONLY while Home is actually open.
//   3. If the recharge STILL hasn't confirmed by then, AND the user has
//      since closed the app entirely, nothing client-side is left running
//      to ever notice the eventual success -- there is no more "later" to
//      check on, because nothing is checking.
//
// A push notification is the only thing that can reach a fully closed
// app. The backend (RechargeService.kt) sends one the moment
// RECHARGE_SUCCESS is reached, carrying the exact same data the reward
// animation needs (orderId, amount, earnedCoins, earnedValue) in the
// payload -- no extra API round-trip required to figure out what to show.
//
// Usage: call PushNotificationService.init() once, early in main() (after
// Firebase.initializeApp(), before runApp()).

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../../routes/app_router.dart';
import '../../data/repositories/user_repository.dart';
import 'coin_animation_signal.dart';
import 'storage_service.dart';

// Top-level function, NOT a class method -- the firebase_messaging plugin
// requires this exact shape (top-level or static, annotated
// @pragma('vm:entry-point')) because it can run in a separate isolate
// when a data message arrives while the app is fully terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Deliberately does nothing beyond letting the OS show the notification
  // (which happens automatically for a message with a `notification`
  // block, even in this background isolate) -- the actual animation only
  // plays once the user taps it and the app comes to the foreground,
  // handled by onMessageOpenedApp/getInitialMessage below. Keeping this
  // handler minimal avoids needing Firebase re-initialized in a throwaway
  // background isolate just to show a coin animation nobody can see yet.
  debugPrint('FCM background message received: ${message.data}');
}

class PushNotificationService {
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // iOS requires this explicitly; Android 13+ (API 33+) also requires a
    // runtime permission prompt now, same call handles both.
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    debugPrint('FCM permission status: ${settings.authorizationStatus}');

    await _registerToken();
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
      UserRepository().updateFcmToken(newToken);
    });

    // App was fully terminated, user tapped the notification to open it.
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _handleRechargeSuccessMessage(initialMessage);
    }

    // App was backgrounded (not terminated), user tapped the notification.
    FirebaseMessaging.onMessageOpenedApp.listen(_handleRechargeSuccessMessage);

    // App was already open/foregrounded when the push arrived -- show the
    // animation immediately, no tap needed, since the user is right there.
    FirebaseMessaging.onMessage.listen(_handleRechargeSuccessMessage);
  }

  static Future<void> _registerToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await UserRepository().updateFcmToken(token);
      }
    } catch (e) {
      // Non-fatal -- see UserRepository.updateFcmToken's own doc comment.
      debugPrint('FCM token registration failed (non-fatal): $e');
    }
  }

  static void _handleRechargeSuccessMessage(RemoteMessage message) {
    final data = message.data;
    if (data['type'] != 'recharge_success') return;

    final orderId = data['orderId'];
    final amountRupees = double.tryParse(data['amountRupees'] ?? '');
    if (orderId == null || amountRupees == null) {
      debugPrint('FCM recharge_success message missing/malformed data: $data');
      return;
    }

    // Reuses the EXACT SAME mechanism home_screen.dart's own async
    // follow-up check already uses (recharge_viewmodel.dart's
    // _stillProcessing path stores this same way) -- the push doesn't
    // trigger the animation directly itself, it just makes sure Home's
    // existing check has fresh data to find, then asks Home to look.
    // Since the backend only ever sends this push once the order has
    // ALREADY resolved to RECHARGE_SUCCESS, Home's very first status
    // check (no 15s wait needed) will resolve immediately.
    StorageService.setPendingCoinAnimation(orderId, amountRupees);

    AppRouter.router.go('/dashboard/home');
    CoinAnimationSignal.fire();
  }
}