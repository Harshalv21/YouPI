import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/otp_input_field.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_input.dart';
import 'kyc_viewmodel.dart';

class AadhaarVerifyScreen extends StatelessWidget {
  const AadhaarVerifyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    String _otp = '';
    return ChangeNotifierProvider(
      create: (_) => KycViewModel(),
      child: Consumer<KycViewModel>(builder: (ctx, vm, _) {
        return Scaffold(
          backgroundColor: AppColors.backgroundPrimary,
          appBar: AppBar(backgroundColor: AppColors.backgroundPrimary),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppDimensions.paddingPage),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(value: 2 / 3, backgroundColor: AppColors.divider,
                    valueColor: const AlwaysStoppedAnimation(AppColors.primary)),
                const SizedBox(height: 8),
                Text('Step 2 of 3', style: AppTextStyles.labelMedium),
                const SizedBox(height: 24),
                Text(AppStrings.aadhaarTitle, style: AppTextStyles.displaySmall),
                Text(AppStrings.aadhaarSubtitle,
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 24),
                YoupiInput(
                  label: 'Aadhaar Number',
                  hint: 'XXXX-XXXX-XXXX',
                  keyboardType: TextInputType.number,
                  maxLength: 12,
                  onChanged: vm.setAadhaar,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 20),
                if (!vm.aadhaarOtpSent)
                  YoupiButton(
                    label: AppStrings.getAadhaarOtp,
                    isLoading: vm.isLoading,
                    onPressed: vm.sendAadhaarOtp,
                  )
                else ...[
                  Text('OTP sent to: ×××××64',
                      style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary)),
                  const SizedBox(height: 16),
                  OtpInputField(onChanged: (v) { _otp = v; }, onCompleted: (v) { _otp = v; }),
                  const SizedBox(height: 12),
                  Center(
                    child: vm.aadhaarCountdown > 0
                        ? Text('Resend OTP in 0:${vm.aadhaarCountdown.toString().padLeft(2, '0')}',
                            style: AppTextStyles.bodySmall)
                        : TextButton(
                            onPressed: vm.sendAadhaarOtp,
                            child: Text('RESEND OTP', style: AppTextStyles.tealLink),
                          ),
                  ),
                  const SizedBox(height: 20),
                  YoupiButton(
                    label: 'Verify Aadhaar',
                    isLoading: vm.isLoading,
                    onPressed: () async {
                      final ok = await vm.verifyAadhaar(_otp);
                      if (ok && ctx.mounted) ctx.push('/kyc/pan');
                    },
                  ),
                ],
                const SizedBox(height: 16),
                // Why Aadhaar expandable
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text('Why Aadhaar?', style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
                  iconColor: AppColors.primary,
                  collapsedIconColor: AppColors.textSecondary,
                  children: [
                    Text(
                      'Aadhaar is India\'s national ID issued by UIDAI. We use it to verify your identity securely and comply with RBI KYC guidelines.',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Social proof
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('+2k JOINED RECENTLY',
                      style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary),
                      textAlign: TextAlign.center),
                ),
                const SizedBox(height: 12),
                Text(AppStrings.aadhaarFooter,
                    style: AppTextStyles.captionText, textAlign: TextAlign.center),
              ],
            ),
          ),
        );
      }),
    );
  }
}
