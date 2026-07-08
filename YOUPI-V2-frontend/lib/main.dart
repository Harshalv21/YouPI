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
import 'package:firebase_core/firebase_core.dart';

 Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();
  ApiService.initialize();
  runApp(const YoupiApp());
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
        ChangeNotifierProvider(create: (_) => WalletViewModel()),
      ],
      child: MaterialApp.router(
        title: 'YouPI',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        routerConfig: AppRouter.router,
      ),
    );
  }
}
