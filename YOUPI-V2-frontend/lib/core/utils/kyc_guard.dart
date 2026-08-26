import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../widgets/youpi_button.dart';
import '../../data/repositories/user_repository.dart';

/// Gate for any real money-moving action that requires completed KYC
/// (Buy/Sell Digital Gold, Fixed Deposits, Loan/BNPL applications, etc.).
///
/// Checks the AUTHORITATIVE backend KYC status (UserRepository.getKycDetails
/// -- panVerified && bankVerified, backed by kyc_records in the DB) rather
/// than any local/mock flag, so a "Skip for now" tap during onboarding can
/// never fool this gate into thinking KYC is done.
///
/// Usage at the top of any gated action's onPressed:
///   onPressed: () async {
///     if (!await KycGuard.requireKyc(context)) return;
///     ... proceed with the real action ...
///   }
class KycGuard {
  // Positive-result cache: once the backend confirms KYC is complete, it
  // stays complete for the session -- no need to re-hit the network on
  // every tap (removes the 1-2s dead time before a gated action responds
  // on slow networks). Negative results are NEVER cached, so a user who
  // completes KYC mid-session is picked up on their next tap.
  static bool _sessionVerified = false;

  /// Returns true if it's safe to proceed (KYC complete). If not, shows a
  /// "please complete your KYC" sheet (GPay/PhonePe-style) and returns
  /// false -- the caller should not continue with the action.
  static Future<bool> requireKyc(BuildContext context, {String? actionLabel}) async {
    if (_sessionVerified) return true;

    bool isVerified;
    try {
      final kyc = await UserRepository().getKycDetails();
      isVerified = kyc.panVerified && kyc.bankVerified;
    } catch (_) {
      // If the status check itself fails, don't silently let a money-moving
      // action through -- treat it the same as "not verified yet".
      isVerified = false;
    }
    if (isVerified) {
      _sessionVerified = true;
      return true;
    }
    if (!context.mounted) return false;

    final wantsToCompleteKyc = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.backgroundCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.verified_user_rounded, color: AppColors.primary, size: 28),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Complete your KYC to continue',
              style: AppTextStyles.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              actionLabel != null
                  ? 'To $actionLabel, we first need to verify your identity — a quick PAN and bank account check, RBI-mandated for all financial services.'
                  : 'To use this feature, we first need to verify your identity — a quick PAN and bank account check, RBI-mandated for all financial services.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            YoupiButton(
              label: 'Complete KYC',
              onPressed: () => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Not now', style: AppTextStyles.tealLink),
            ),
          ],
        ),
      ),
    );

    if (wantsToCompleteKyc == true && context.mounted) {
      context.push('/kyc/intro');
    }
    return false;
  }
}