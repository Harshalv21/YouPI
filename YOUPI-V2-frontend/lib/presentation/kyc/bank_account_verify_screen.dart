import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_input.dart';
import 'kyc_viewmodel.dart';

/// NEW screen — bank account verification via Eko, step 4 of 4 in the
/// KYC sequence. Shares the same KycViewModel instance as the rest of
/// the /kyc/* flow (provided once by the ShellRoute in app_router.dart).
class BankAccountVerifyScreen extends StatelessWidget {
  const BankAccountVerifyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<KycViewModel>();
    final ctx = context;
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(backgroundColor: AppColors.backgroundPrimary),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LinearProgressIndicator(value: 4 / 4, backgroundColor: AppColors.divider,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary)),
            const SizedBox(height: 8),
            Text('Step 4 of 4', style: AppTextStyles.labelMedium),
            const SizedBox(height: 24),
            Text('Bank Account Verification', style: AppTextStyles.displaySmall),
            const SizedBox(height: 8),
            Text(
              'Used for refunds, gold redemption payouts, and loan disbursement.',
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            YoupiInput(
              label: 'Bank Account Number',
              hint: '1234567890',
              keyboardType: TextInputType.number,
              maxLength: 18,
              onChanged: (v) => vm.setBankAccountNumber(v),
            ),
            const SizedBox(height: 16),
            YoupiInput(
              label: 'IFSC Code',
              hint: 'SBIN0001234',
              maxLength: 11,
              onChanged: (v) => vm.setBankIfsc(v.toUpperCase()),
            ),
            const SizedBox(height: 12),
            YoupiButton(
              label: vm.bankVerified ? 'Verified ✓' : 'Verify Bank Account',
              isLoading: vm.isLoading,
              onPressed: (vm.isBankFormatValid && !vm.bankVerified)
                  ? () => vm.verifyBankAccountWithBackend()
                  : null,
            ),
            if (vm.bankVerified)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.success.withOpacity(0.4)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        [
                          if (vm.bankAccountHolderName != null) vm.bankAccountHolderName,
                          if (vm.bankName != null) vm.bankName,
                        ].where((s) => s != null).join(' • '),
                        style: AppTextStyles.bodySmall.copyWith(color: AppColors.success),
                      ),
                    ),
                  ]),
                ),
              ),
            if (vm.bankError != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(vm.bankError!,
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
              ),
            const SizedBox(height: 32),
            YoupiButton(
              label: 'Complete KYC',
              isLoading: vm.isLoading,
              onPressed: vm.bankVerified
                  ? () async {
                final ok = await vm.completeKyc();
                if (ok && ctx.mounted) ctx.go('/kyc/success');
              }
                  : null,
            ),
            const SizedBox(height: 12),
            Center(
              child: TextButton(
                onPressed: () async {
                  final ok = await vm.completeKyc();
                  if (ok && ctx.mounted) ctx.go('/kyc/success');
                },
                child: Text('Skip for now',
                    style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}