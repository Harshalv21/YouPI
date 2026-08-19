import 'package:flutter/material.dart';
import '../core/widgets/coming_soon_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/services/storage_service.dart';
import '../presentation/splash/splash_screen.dart';
import '../presentation/onboarding/welcome_screen.dart';
import '../presentation/onboarding/onboarding_carousel_screen.dart';
import '../presentation/onboarding/onboarding_questions_screen.dart'; // NEW
import '../presentation/onboarding/smartsave_eligibility_screen.dart';
import '../presentation/auth/mobile_entry_screen.dart';
import '../presentation/auth/otp_verify_screen.dart';
import '../presentation/auth/user_profile_setup_screen.dart';
import '../presentation/auth/mpin_entry_screen.dart';
import '../presentation/auth/mpin_setup_screen.dart';
import '../presentation/auth/login_mpin_screen.dart';
import '../presentation/kyc/kyc_viewmodel.dart';
import '../presentation/kyc/kyc_intro_screen.dart';
import '../presentation/kyc/aadhaar_verify_screen.dart';
import '../presentation/kyc/pan_verify_screen.dart';
import '../presentation/kyc/bank_account_verify_screen.dart';
import '../presentation/kyc/kyc_success_screen.dart';
import '../presentation/dashboard/home_screen.dart';
import '../presentation/recharge/recharge_home_screen.dart';
import '../presentation/recharge/browse_plans_screen.dart';
import '../presentation/recharge/smartsave_advantage_screen.dart';
import '../presentation/recharge/emi_selection_screen.dart';
import '../presentation/recharge/recharge_success_screen.dart';
import '../presentation/invest/invest_hub_screen.dart';
import '../presentation/invest/digital_gold_screen.dart';
import '../presentation/invest/fd_calculator_screen.dart';
import '../presentation/invest/portfolio_screen.dart';
import '../presentation/bnpl/bnpl_hub_screen.dart';
import '../presentation/bnpl/bnpl_apply_step1_screen.dart';
import '../presentation/bnpl/bnpl_apply_step2_screen.dart';
import '../presentation/bnpl/bnpl_apply_step3_screen.dart';
import '../presentation/bnpl/bnpl_not_approved_screen.dart';
import '../presentation/bnpl/smart_deposit_screen.dart';
import '../presentation/bnpl/bnpl_approved_screen.dart';
import '../presentation/loan/loan_apply_step1_screen.dart';
import '../presentation/loan/loan_apply_step2_screen.dart';
import '../presentation/loan/loan_apply_step3_screen.dart';
import '../presentation/loan/loan_approved_screen.dart';
import '../presentation/loan/my_loans_screen.dart';
import '../presentation/loan/nbfc_credit_screen.dart';
import '../presentation/wallet/wallet_screen.dart';
import '../presentation/wallet/add_money_screen.dart';
import '../presentation/wallet/transaction_history_screen.dart';
import '../presentation/settings/settings_screen.dart';
import '../presentation/settings/privacy_policy_screen.dart';
import '../presentation/settings/terms_of_service_screen.dart';
import '../presentation/settings/help_support_screen.dart';

class AppRouter {
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();

  static GoRouter? _router;
  static GoRouter get router => _router ??= _buildRouter();

  static GoRouter _buildRouter() => GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    redirect: (context, state) async {
      final hasToken = await StorageService.hasToken();
      final isGuest = await StorageService.isGuestMode();
      final path = state.matchedLocation;

      if (path.startsWith('/splash') ||
          path.startsWith('/onboarding') ||
          path.startsWith('/auth')) {
        return null;
      }

      if (!hasToken && !isGuest) return '/auth/mobile';

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (c, s) => const SplashScreen()),
      GoRoute(path: '/onboarding/welcome', builder: (c, s) => const WelcomeScreen()),
      GoRoute(path: '/onboarding/carousel', builder: (c, s) => const OnboardingCarouselScreen()),
      // NEW: 5-question financial profile, shown after the carousel
      // (both Skip and Get Started land here now), before phone entry.
      // No backend call happens inside this screen -- answers are cached
      // in memory (OnboardingAnswerCache) and submitted after OTP
      // verification succeeds, only for isNewUser == true.
      GoRoute(
        path: '/onboarding/questions',
        builder: (c, s) => OnboardingQuestionsScreen(
          onComplete: (answers) {
            OnboardingAnswerCache.instance.store(answers);
            final eligible = computeSmartSaveEligibility(answers);
            c.go('/onboarding/eligibility', extra: eligible);
          },
        ),
      ),
      GoRoute(
        path: '/onboarding/eligibility',
        builder: (c, s) => SmartSaveEligibilityScreen(
          isEligible: s.extra as bool? ?? false,
          onContinue: () => c.go('/auth/mobile'),
        ),
      ),
      GoRoute(path: '/auth/mobile', builder: (c, s) => const MobileEntryScreen()),
      GoRoute(
        path: '/auth/otp',
        builder: (c, s) {
          final extra = s.extra;
          if (extra is Map) {
            return OtpVerifyScreen(
              mobile: extra['mobile'] as String? ?? '',
              isRecovery: extra['isRecovery'] == true,
            );
          }
          return OtpVerifyScreen(mobile: extra as String? ?? '');
        },
      ),
      GoRoute(path: '/auth/mpin-entry', builder: (c, s) => const MpinEntryScreen()),
      GoRoute(
        path: '/auth/login-mpin',
        builder: (c, s) => LoginMpinScreen(mobile: s.extra as String?),
      ),
      GoRoute(path: '/auth/profile-setup', builder: (c, s) => const UserProfileSetupScreen()),
      GoRoute(
        path: '/auth/mpin-setup',
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return MpinSetupScreen(isReset: extra?['isReset'] == true);
        },
      ),
      ShellRoute(
        builder: (context, state, child) => ChangeNotifierProvider(
          create: (_) => KycViewModel(),
          child: child,
        ),
        routes: [
          GoRoute(path: '/kyc/intro', builder: (c, s) => const KycIntroScreen()),
          GoRoute(path: '/kyc/aadhaar', builder: (c, s) => const AadhaarVerifyScreen()),
          GoRoute(path: '/kyc/pan', builder: (c, s) => const PanVerifyScreen()),
          GoRoute(path: '/kyc/bank-account', builder: (c, s) => const BankAccountVerifyScreen()),
          GoRoute(path: '/kyc/success', builder: (c, s) => const KycSuccessScreen()),
        ],
      ),
      GoRoute(path: '/plans/browse', builder: (c, s) => const BrowsePlansScreen()),
      GoRoute(path: '/plans/smartsave', builder: (c, s) => const SmartSaveAdvantageScreen()),
      GoRoute(path: '/plans/emi-select', builder: (c, s) => const EmiSelectionScreen()),
      GoRoute(path: '/plans/success', builder: (c, s) => const RechargeSuccessScreen()),
      GoRoute(path: '/invest/gold', builder: (c, s) => const DigitalGoldScreen()),
      GoRoute(path: '/invest/fd', builder: (c, s) => const FdCalculatorScreen()),
      GoRoute(path: '/invest/portfolio', builder: (c, s) => const PortfolioScreen()),
      GoRoute(path: '/bnpl/apply/step1', builder: (c, s) => const BnplApplyStep1Screen()),
      GoRoute(path: '/bnpl/apply/step2', builder: (c, s) => const BnplApplyStep2Screen()),
      GoRoute(path: '/bnpl/apply/step3', builder: (c, s) => const BnplApplyStep3Screen()),
      GoRoute(path: '/bnpl/not-approved', builder: (c, s) => const BnplNotApprovedScreen()),
      GoRoute(path: '/bnpl/smart-deposit', builder: (c, s) => const SmartDepositScreen()),
      GoRoute(path: '/bnpl/approved', builder: (c, s) => const BnplApprovedScreen()),
      GoRoute(path: '/loan/apply/step1', builder: (c, s) => const LoanApplyStep1Screen()),
      GoRoute(path: '/loan/apply/step2', builder: (c, s) => const LoanApplyStep2Screen()),
      GoRoute(path: '/loan/apply/step3', builder: (c, s) => const LoanApplyStep3Screen()),
      GoRoute(path: '/loan/approved', builder: (c, s) => const LoanApprovedScreen()),
      GoRoute(path: '/loan/my-loans', builder: (c, s) => const MyLoansScreen()),
      GoRoute(path: '/loan/nbfc-credit', builder: (c, s) => const NbfcCreditScreen()),
      GoRoute(path: '/wallet/add', builder: (c, s) => const AddMoneyScreen()),
      GoRoute(path: '/wallet/history', builder: (c, s) => const TransactionHistoryScreen()),
      GoRoute(path: '/settings/edit-profile', builder: (c, s) => const EditProfileScreen()),
      GoRoute(path: '/settings/notifications', builder: (c, s) => const NotificationsSettingsScreen()),
      GoRoute(path: '/settings/change-mpin', builder: (c, s) => const ChangeMpinScreen()),
      GoRoute(path: '/settings/privacy-policy', builder: (c, s) => const PrivacyPolicyScreen()),
      GoRoute(path: '/settings/terms-of-service', builder: (c, s) => const TermsOfServiceScreen()),
      GoRoute(path: '/settings/help-support', builder: (c, s) => const HelpSupportScreen()),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard/home',
            builder: (c, s) {
              final extra = s.extra as Map?;
              return HomeScreen(
                justEarnedCoin: extra?['justEarnedCoin'] == true,
                debugBumpCoin: extra?['debugBumpCoin'] == true,
                earnedCoins: extra?['earnedCoins'] as int?,
                earnedValue: (extra?['earnedValue'] as num?)?.toDouble(),
              );
            },
          ),
          GoRoute(path: '/dashboard/plans', builder: (c, s) => const RechargeHomeScreen()),
          GoRoute(path: '/dashboard/invest', builder: (c, s) => const InvestHubScreen()),
          GoRoute(path: '/dashboard/wallet', builder: (c, s) => const WalletScreen()),
          GoRoute(path: '/dashboard/settings', builder: (c, s) => const SettingsScreen()),
          GoRoute(path: '/dashboard/bnpl', builder: (c, s) => const BnplHubScreen()),
        ],
      ),
    ],
  );
}

class MainShell extends StatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  static const _tabRoutes = [
    '/dashboard/home',
    '/dashboard/plans',
    '/dashboard/invest',
    '/dashboard/wallet',
    '/dashboard/settings',
  ];

  static const _lockedTabs = <int, String>{};

  void _handleTabTap(int index) {
    if (_lockedTabs.containsKey(index)) {
      showComingSoonDialog(context, featureName: _lockedTabs[index]!);
      return;
    }
    context.go(_tabRoutes[index]);
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    final matchedIndex =
    _tabRoutes.indexWhere((r) => location.startsWith(r));

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: _YoupiBottomNav(
        currentIndex: matchedIndex,
        onTap: _handleTabTap,
      ),
    );
  }
}

class _YoupiBottomNav extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onTap;

  const _YoupiBottomNav({required this.currentIndex, required this.onTap});

  static const _items = [
    BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
    BottomNavigationBarItem(icon: Icon(Icons.wifi_rounded), label: 'Plans'),
    BottomNavigationBarItem(icon: Icon(Icons.trending_up_rounded), label: 'Invest'),
    BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_rounded), label: 'Wallet'),
    BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final hasActive = currentIndex >= 0;
    return BottomNavigationBar(
      currentIndex: hasActive ? currentIndex : 0,
      onTap: onTap,
      items: _items,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: hasActive ? null : Colors.grey,
    );
  }
}