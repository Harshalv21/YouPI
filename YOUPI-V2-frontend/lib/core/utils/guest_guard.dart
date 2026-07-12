import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';
import '../services/storage_service.dart';
import '../widgets/youpi_button.dart';

/// Gate for any real operation (Add Money, Send Money, Apply for BNPL/Loan,
/// start KYC, save profile edits, confirm a recharge, etc.).
///
/// Guests can browse the dashboard freely, but the moment they try to *do*
/// something, this prompts them to register first instead of letting the
/// request silently fail against a backend that has no account for them.
///
/// Usage at the top of any action's onPressed:
///   onPressed: () async {
///     if (!await GuestGuard.requireAuth(context)) return;
///     ... proceed with the real action ...
///   }
class GuestGuard {
  /// Returns true if it's safe to proceed (not a guest). If the person is a
  /// guest, shows a "please register" sheet and returns false -- the caller
  /// should not continue with the action.
  static Future<bool> requireAuth(BuildContext context, {String? actionLabel}) async {
    final isGuest = await StorageService.isGuestMode();
    if (!isGuest) return true;
    if (!context.mounted) return false;

    final wantsToRegister = await showModalBottomSheet<bool>(
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
                child: const Icon(Icons.person_add_rounded, color: AppColors.primary, size: 28),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Create an account to continue',
              style: AppTextStyles.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              actionLabel != null
                  ? 'You need a registered account to $actionLabel. It only takes 2 minutes.'
                  : 'You need a registered account for this. It only takes 2 minutes.',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            YoupiButton(
              label: 'Register Now',
              onPressed: () => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Maybe later', style: AppTextStyles.tealLink),
            ),
          ],
        ),
      ),
    );

    if (wantsToRegister == true && context.mounted) {
      // Guest is exiting browse-only mode -- clear the flag so the router
      // stops treating them as a guest once they land back on a real route.
      await StorageService.clearGuestMode();
      if (context.mounted) context.go('/onboarding/carousel');
    }
    return false;
  }
}