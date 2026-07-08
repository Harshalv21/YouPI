import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_input.dart';
import 'auth_viewmodel.dart';

class UserProfileSetupScreen extends StatefulWidget {
  const UserProfileSetupScreen({super.key});
  @override
  State<UserProfileSetupScreen> createState() => _UserProfileSetupScreenState();
}

class _UserProfileSetupScreenState extends State<UserProfileSetupScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  DateTime? _selectedDob;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(BuildContext context, AuthViewModel vm) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000, 1, 1),
      firstDate: DateTime(1940),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _selectedDob = picked);
      vm.setDob(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AuthViewModel(),
      child: Consumer<AuthViewModel>(builder: (ctx, vm, _) {
        return Scaffold(
          backgroundColor: AppColors.backgroundPrimary,
          appBar: AppBar(backgroundColor: AppColors.backgroundPrimary),
          body: Padding(
            padding: const EdgeInsets.all(AppDimensions.paddingPage),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Progress
                LinearProgressIndicator(value: 1 / 3, backgroundColor: AppColors.divider,
                    valueColor: const AlwaysStoppedAnimation(AppColors.primary)),
                const SizedBox(height: 8),
                Text('Step 1 of 3', style: AppTextStyles.labelMedium),
                const SizedBox(height: 24),
                Text(AppStrings.profileSetupTitle, style: AppTextStyles.displaySmall),
                Text(AppStrings.profileSetupSubtitle,
                    style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 32),
                YoupiInput(
                  label: AppStrings.fullName,
                  hint: 'e.g. Siddhant Verma',
                  controller: _nameCtrl,
                  onChanged: vm.setName,
                ),
                const SizedBox(height: 16),
                // DOB picker
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(AppStrings.dateOfBirth, style: AppTextStyles.inputLabel),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: () => _pickDate(ctx, vm),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          color: AppColors.backgroundCard,
                          borderRadius: BorderRadius.circular(AppDimensions.radiusInput),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _selectedDob != null
                                    ? '${_selectedDob!.day.toString().padLeft(2, '0')}/${_selectedDob!.month.toString().padLeft(2, '0')}/${_selectedDob!.year}'
                                    : 'DD/MM/YYYY',
                                style: _selectedDob != null
                                    ? AppTextStyles.inputValue
                                    : AppTextStyles.inputValue.copyWith(color: AppColors.textSecondary),
                              ),
                            ),
                            const Icon(Icons.calendar_today_rounded, color: AppColors.textSecondary, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                YoupiInput(
                  label: '${AppStrings.emailAddress} (optional)',
                  hint: 'your@email.com',
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: vm.setEmail,
                ),
                const Spacer(),
                YoupiButton(
                  label: AppStrings.continueBtn,
                  onPressed: vm.validateStep1() ? () => ctx.push('/auth/mpin-setup') : null,
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}
