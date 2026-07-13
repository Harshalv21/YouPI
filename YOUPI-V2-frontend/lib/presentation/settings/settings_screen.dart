import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/services/storage_service.dart';
import '../../core/utils/guest_guard.dart';
import '../../core/widgets/youpi_button.dart';
import '../../core/widgets/youpi_card.dart';
import '../../core/widgets/youpi_input.dart';
import '../../data/repositories/auth_repository.dart';
import '../dashboard/home_viewmodel.dart';
import 'settings_viewmodel.dart';

// ─────────── Settings ───────────
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<SettingsViewModel>().loadProfile();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    final user = vm.user;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(title: const Text('Settings'), backgroundColor: AppColors.backgroundPrimary),
      body: vm.isLoading && user == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Avatar row
          Center(
            child: Column(children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                    color: AppColors.primary, shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: AppColors.primaryGlow, blurRadius: 16)]),
                child: Center(
                    child: Text(user?.initials ?? 'Y',
                        style: AppTextStyles.displaySmall.copyWith(color: AppColors.backgroundPrimary))),
              ),
              const SizedBox(height: 8),
              Text(user?.name.isNotEmpty == true ? user!.name : 'Your Name',
                  style: AppTextStyles.headlineMedium),
              Text(user?.mobile ?? '', style: AppTextStyles.bodySmall),
              if (user?.isKycVerified == true)
                Chip(
                  label: Text('KYC Verified', style: AppTextStyles.chipText.copyWith(color: AppColors.success)),
                  backgroundColor: AppColors.success.withOpacity(0.1),
                  side: const BorderSide(color: AppColors.success),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
            ]),
          ),
          const SizedBox(height: 24),
          Text('Account', style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          ...[
            _SettingsTile('Edit Profile', Icons.person_outline_rounded, () async {
              if (!await GuestGuard.requireAuth(context, actionLabel: 'edit your profile')) return;
              if (context.mounted) context.push('/settings/edit-profile');
            }),
            _SettingsTile('Change MPIN', Icons.lock_outline_rounded, () async {
              if (!await GuestGuard.requireAuth(context, actionLabel: 'change your MPIN')) return;
              if (context.mounted) context.push('/settings/change-mpin');
            }),
            _SettingsTile('Notifications', Icons.notifications_none_rounded, () => context.push('/settings/notifications')),
          ],
          const SizedBox(height: 16),
          Text('Support', style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          ...[
            _SettingsTile('Help & Support', Icons.help_outline_rounded,
                    () => _showComingSoon(context, 'Help & Support')),
            _SettingsTile('Privacy Policy', Icons.privacy_tip_outlined,
                    () => _showComingSoon(context, 'Privacy Policy')),
            _SettingsTile('Terms of Service', Icons.description_outlined,
                    () => _showComingSoon(context, 'Terms of Service')),
          ],
          const SizedBox(height: 16),
          YoupiCard(
            onTap: () async {
              await StorageService.clearAll();
              if (context.mounted) context.go('/onboarding/welcome');
            },
            child: Row(children: [
              const Icon(Icons.logout_rounded, color: AppColors.error, size: 20),
              const SizedBox(width: 12),
              Text('Sign Out', style: AppTextStyles.labelLarge.copyWith(color: AppColors.error)),
            ]),
          ),
          const SizedBox(height: 8),
          Text('YOUPI • Nexospendz Finothrive • v1.0.0',
              style: AppTextStyles.captionText, textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

void _showComingSoon(BuildContext context, String feature) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.backgroundCard,
      title: Text(feature, style: AppTextStyles.headlineSmall),
      content: Text(
        '$feature will be available soon.',
        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text('OK', style: AppTextStyles.tealLink),
        ),
      ],
    ),
  );
}

class _SettingsTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _SettingsTile(this.label, this.icon, this.onTap);
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: YoupiCard(onTap: onTap, child: Row(children: [
      Icon(icon, color: AppColors.textSecondary, size: 20),
      const SizedBox(width: 12),
      Expanded(child: Text(label, style: AppTextStyles.labelLarge)),
      const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
    ])),
  );
}

// ─────────── Edit Profile ───────────
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _initialized = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  void _initFields(dynamic user) {
    if (_initialized || user == null) return;
    _nameCtrl.text = user.name;
    _emailCtrl.text = user.email;
    _initialized = true;
  }

  Future<void> _save(BuildContext context) async {
    final vm = context.read<SettingsViewModel>();
    final ok = await vm.updateProfile(
      fullName: _nameCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
    );
    if (!context.mounted) return;
    if (ok) {
      // SettingsViewModel now has the fresh name/email, but HomeViewModel
      // (drives "Welcome back, {name}" on the dashboard) is a *separate*
      // cached instance that has no idea this just changed. Without this,
      // the save genuinely succeeds but looks like it "didn't update"
      // because Home still shows the old name until the app is fully
      // restarted or the user pulls-to-refresh there manually.
      unawaited(context.read<HomeViewModel>().loadHome());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Profile updated!'), backgroundColor: AppColors.success));
      context.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(vm.error ?? 'Update failed'), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SettingsViewModel>();
    _initFields(vm.user);

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(title: const Text('Edit Profile'), backgroundColor: AppColors.backgroundPrimary),
      body: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          YoupiInput(label: 'Full Name', controller: _nameCtrl),
          const SizedBox(height: 16),
          YoupiInput(label: 'Email', controller: _emailCtrl, keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 16),
          YoupiInput(label: 'Mobile', hint: vm.user?.mobile ?? '', readOnly: true),
          const Spacer(),
          YoupiButton(
            label: 'Save Changes',
            isLoading: vm.isLoading,
            onPressed: () => _save(context),
          ),
        ]),
      ),
    );
  }
}

// ─────────── Notifications Settings ───────────
class NotificationsSettingsScreen extends StatefulWidget {
  const NotificationsSettingsScreen({super.key});
  @override State<NotificationsSettingsScreen> createState() => _NotificationsSettingsScreenState();
}

class _NotificationsSettingsScreenState extends State<NotificationsSettingsScreen> {
  bool _rechargePushOn = true;
  bool _goldAlertsOn = false;
  bool _emiRemindersOn = true;
  bool _offersOn = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(title: const Text('Notifications'), backgroundColor: AppColors.backgroundPrimary),
      body: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _SwitchTile('Recharge Alerts', _rechargePushOn, (v) => setState(() => _rechargePushOn = v)),
          _SwitchTile('Gold Price Alerts', _goldAlertsOn, (v) => setState(() => _goldAlertsOn = v)),
          _SwitchTile('EMI Reminders', _emiRemindersOn, (v) => setState(() => _emiRemindersOn = v)),
          _SwitchTile('Offers & Promotions', _offersOn, (v) => setState(() => _offersOn = v)),
        ]),
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final String label;
  final bool value;
  final void Function(bool) onChanged;
  const _SwitchTile(this.label, this.value, this.onChanged);
  @override Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: YoupiCard(child: Row(children: [
      Expanded(child: Text(label, style: AppTextStyles.labelLarge)),
      Switch(value: value, onChanged: onChanged, activeColor: AppColors.primary),
    ])),
  );
}

// ─────────── Change MPIN ───────────
class ChangeMpinScreen extends StatefulWidget {
  const ChangeMpinScreen({super.key});
  @override State<ChangeMpinScreen> createState() => _ChangeMpinScreenState();
}

class _ChangeMpinScreenState extends State<ChangeMpinScreen> {
  final AuthRepository _authRepo = AuthRepository();

  String _currentMpin = '';
  String _newMpin = '';
  String _step = 'verify'; // verify | new | confirm
  String _confirmNew = '';
  bool _isVerifying = false;
  String? _errorText;

  void _onDigit(String d) {
    if (_isVerifying) return;
    setState(() {
      _errorText = null;
      if (_step == 'verify' && _currentMpin.length < 4) {
        _currentMpin += d;
        if (_currentMpin.length == 4) _verifyAndProceed();
      } else if (_step == 'new' && _newMpin.length < 4) {
        _newMpin += d;
        if (_newMpin.length == 4) _step = 'confirm';
      } else if (_step == 'confirm' && _confirmNew.length < 4) {
        _confirmNew += d;
        if (_confirmNew.length == 4) _saveMpin();
      }
    });
  }

  void _onDelete() {
    if (_isVerifying) return;
    setState(() {
      if (_step == 'verify' && _currentMpin.isNotEmpty) _currentMpin = _currentMpin.substring(0, _currentMpin.length - 1);
      else if (_step == 'new' && _newMpin.isNotEmpty) _newMpin = _newMpin.substring(0, _newMpin.length - 1);
      else if (_step == 'confirm' && _confirmNew.isNotEmpty) _confirmNew = _confirmNew.substring(0, _confirmNew.length - 1);
    });
  }

  /// Verifies the current MPIN against the BACKEND (not a local hash) —
  /// this ensures attempt-limits/lockout are enforced server-side and can't
  /// be bypassed by offline brute-forcing a locally stored hash.
  Future<void> _verifyAndProceed() async {
    final mobile = context.read<SettingsViewModel>().user?.mobile;
    if (mobile == null || mobile.isEmpty) {
      setState(() {
        _currentMpin = '';
        _errorText = 'Could not verify — profile not loaded. Try again.';
      });
      return;
    }

    setState(() => _isVerifying = true);
    final result = await _authRepo.loginWithMpin(mobile, _currentMpin);
    if (!mounted) return;

    if (result.success) {
      setState(() {
        _isVerifying = false;
        _step = 'new';
      });
    } else {
      setState(() {
        _isVerifying = false;
        _currentMpin = '';
        _errorText = result.attemptsRemaining != null
            ? 'Wrong MPIN. ${result.attemptsRemaining} attempt(s) left.'
            : (result.message ?? 'Incorrect MPIN. Try again.');
      });
    }
  }

  Future<void> _saveMpin() async {
    if (_newMpin != _confirmNew) {
      setState(() {
        _confirmNew = '';
        _step = 'new';
        _errorText = 'MPINs do not match. Try again.';
      });
      return;
    }
    setState(() => _isVerifying = true);
    try {
      // Update on the backend (source of truth) — local hash kept only
      // as a convenience cache for any local-only checks elsewhere.
      await _authRepo.setupMpin(_newMpin);
      await StorageService.saveMpin(_newMpin);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _errorText = 'Could not update MPIN. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dots = _step == 'verify' ? _currentMpin : _step == 'new' ? _newMpin : _confirmNew;
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(backgroundColor: AppColors.backgroundPrimary, title: const Text('Change MPIN')),
      body: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(children: [
          Text(_step == 'verify' ? 'Enter Current MPIN' : _step == 'new' ? 'Enter New MPIN' : 'Confirm New MPIN',
              style: AppTextStyles.headlineMedium, textAlign: TextAlign.center),
          const SizedBox(height: 40),
          Row(mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) => Container(
                margin: const EdgeInsets.symmetric(horizontal: 8),
                width: 16, height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < dots.length ? AppColors.primary : AppColors.divider,
                ),
              ))),
          const SizedBox(height: 16),
          if (_isVerifying)
            const CircularProgressIndicator(color: AppColors.primary),
          if (_errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_errorText!, style: AppTextStyles.errorText, textAlign: TextAlign.center),
            ),
          const Spacer(),
          for (final row in [['1','2','3'],['4','5','6'],['7','8','9'],['','0','⌫']])
            Row(mainAxisAlignment: MainAxisAlignment.center,
                children: row.map((d) => GestureDetector(
                  onTap: () => d == '⌫' ? _onDelete() : d.isNotEmpty ? _onDigit(d) : null,
                  child: Container(
                    width: 80, height: 72, margin: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: d.isEmpty ? Colors.transparent : AppColors.backgroundCard,
                        borderRadius: BorderRadius.circular(12),
                        border: d.isEmpty ? null : Border.all(color: AppColors.divider)),
                    child: Center(
                      child: d == '⌫'
                          ? const Icon(Icons.backspace_rounded, color: AppColors.textSecondary, size: 20)
                          : Text(d, style: AppTextStyles.headlineLarge),
                    ),
                  ),
                )).toList()),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}