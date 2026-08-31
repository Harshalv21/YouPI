import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:youpi/presentation/auth/auth_viewmodel.dart';
import 'routes/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/services/api_service.dart';
import 'presentation/splash/splash_viewmodel.dart';
import 'presentation/dashboard/home_viewmodel.dart';
import 'presentation/recharge/recharge_viewmodel.dart';
import 'presentation/invest/invest_viewmodel.dart';
import 'presentation/goals/goals_viewmodel.dart';
import 'package:youpi/presentation/settings/settings_viewmodel.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/services/push_notification_service.dart';
import 'core/services/app_lock_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  ApiService.initialize();
  runApp(const YoupiApp());

  // Fire-and-forget, after runApp -- the permission prompt + token fetch
  // shouldn't delay the splash screen. See push_notification_service.dart
  // for why this exists (closed-app recharge-success animation delivery).
  PushNotificationService.init();
}


class YoupiApp extends StatelessWidget {
  const YoupiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthViewModel()),
        ChangeNotifierProvider(create: (_) => SplashViewModel()),
        ChangeNotifierProvider(create: (_) => HomeViewModel()),
        ChangeNotifierProvider(create: (_) => RechargeViewModel()),
        ChangeNotifierProvider(create: (_) => InvestViewModel()),
        ChangeNotifierProvider(create: (_) => GoalsViewModel()),
        ChangeNotifierProvider(create: (_) => WalletViewModel()),
        ChangeNotifierProvider(create: (_) => SettingsViewModel()),
      ],
      child: AppLockGate(
        child: MaterialApp.router(
          title: 'YouPI',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.darkTheme,
          routerConfig: AppRouter.router,
        ),
      ),
    );
  }
}