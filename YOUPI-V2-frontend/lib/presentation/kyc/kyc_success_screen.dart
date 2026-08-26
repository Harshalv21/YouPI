import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';

class KycSuccessScreen extends StatelessWidget {
  const KycSuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // BUG FIX (back button exits app / CONFIRMED root cause of the reported
    // bug): bank_account_verify_screen.dart reaches this screen via
    // ctx.go('/kyc/success') -- a go(), not a push() -- which *replaces* the
    // entire navigator stack. So this screen always sits at the root with
    // nothing left to pop, and until now had no PopScope guard at all (unlike
    // kyc_intro_screen.dart, which already got this fix). Android's back
    // button was closing the app here. PopScope intercepts that and sends the
    // user to the dashboard instead of letting the OS kill the app.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          context.go('/dashboard/home');
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        body: SafeArea(
          // BUG FIX: same Column+Spacer overflow issue as mpin_entry_screen.dart
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
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(),
                        Center(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: 1),
                            duration: const Duration(milliseconds: 800),
                            builder: (ctx, v, _) => Transform.scale(
                              scale: v,
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.primary, width: 3),
                                  boxShadow: [BoxShadow(color: AppColors.primaryGlow, blurRadius: 30, spreadRadius: 5)],
                                ),
                                child: const Icon(Icons.check_rounded, color: AppColors.primary, size: 60),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        Text(AppStrings.kycSuccessTitle, style: AppTextStyles.displayMedium, textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        Text(AppStrings.kycSuccessSubtitle,
                            style: AppTextStyles.bodyLarge.copyWith(color: AppColors.textSecondary),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 32),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: ['BNPL', 'Digital Gold', 'Fixed Deposits', 'Wallet'].map((f) => Chip(
                            label: Text(f, style: AppTextStyles.chipText.copyWith(color: AppColors.primary)),
                            backgroundColor: AppColors.primary.withOpacity(0.1),
                            side: const BorderSide(color: AppColors.primary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          )).toList(),
                        ),
                        const Spacer(),
                        YoupiButton(
                          label: AppStrings.goToDashboard,
                          onPressed: () => context.go('/dashboard/home'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}