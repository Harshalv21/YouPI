import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_dimensions.dart';
import '../../core/constants/app_strings.dart';
import '../../core/constants/app_text_styles.dart';
import '../../core/services/storage_service.dart';
import '../../data/repositories/auth_repository.dart';
import 'package:local_auth/local_auth.dart';

class MpinSetupScreen extends StatefulWidget {
  const MpinSetupScreen({super.key});
  @override
  State<MpinSetupScreen> createState() => _MpinSetupScreenState();
}

class _MpinSetupScreenState extends State<MpinSetupScreen> {
  final AuthRepository _authRepo = AuthRepository();

  String _mpin = '';
  String _confirmMpin = '';
  bool _isConfirming = false;
  bool _isLoading = false;

  void _onDigit(String d) {
    if (_isLoading) return; // saving ke dauraan input block
    setState(() {
      if (!_isConfirming && _mpin.length < 4) {
        _mpin += d;
        if (_mpin.length == 4) {
          // weak MPIN check pehle confirm pe jaane se
          final err = _validateMpin(_mpin);
          if (err != null) {
            _showError(err);
            _mpin = '';
            return;
          }
          _isConfirming = true;
        }
      } else if (_isConfirming && _confirmMpin.length < 4) {
        _confirmMpin += d;
        if (_confirmMpin.length == 4) _saveMpin();
      }
    });
  }

  void _onDelete() {
    if (_isLoading) return;
    setState(() {
      if (_isConfirming && _confirmMpin.isNotEmpty) {
        _confirmMpin = _confirmMpin.substring(0, _confirmMpin.length - 1);
      } else if (!_isConfirming && _mpin.isNotEmpty) {
        _mpin = _mpin.substring(0, _mpin.length - 1);
      }
    });
  }

  /// Basic weak-MPIN validation. Returns error message or null if OK.
  String? _validateMpin(String mpin) {
    if (mpin.length != 4) return 'MPIN must be 4 digits';
    // Saare same digit: 0000, 1111...
    if (RegExp(r'^(\d)\1{3}$').hasMatch(mpin)) {
      return 'MPIN too weak. Avoid repeating digits.';
    }
    // Sequential: 1234, 2345, 0123
    const seqUp = '0123456789';
    const seqDown = '9876543210';
    if (seqUp.contains(mpin) || seqDown.contains(mpin)) {
      return 'MPIN too weak. Avoid sequences like 1234.';
    }
    return null;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error),
    );
  }

  Future<void> _saveMpin() async {
    // Mismatch → dono clear karo, pehli screen pe wapas
    if (_mpin != _confirmMpin) {
      setState(() {
        _mpin = '';
        _confirmMpin = '';
        _isConfirming = false;
      });
      _showError('MPINs do not match. Please set it again.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Local pe save (biometric/offline unlock ke liye)
      await StorageService.saveMpin(_mpin);

      // 2. Backend pe bhi save — taaki dusre device pe kaam kare.
      //    (token na ho / backend down ho to local save phir bhi ho chuka;
      //     is line ko fail hone par bhi flow aage badhne dete hain.)
      try {
        await _authRepo.setupMpin(_mpin);
      } catch (e) {
        // Backend save fail — abhi block mat karo (login/deploy pending).
        debugPrint('MPIN backend sync failed: $e');
      }

      if (mounted) {
        // Was previously never called anywhere in the app, so the
        // biometric-first unlock already built into MpinEntryScreen never
        // actually triggered for any user. Ask once, right after MPIN setup
        // -- the natural moment, same as Google Pay/PhonePe do it.
        await _maybeEnableBiometric();
        if (mounted) context.go('/kyc/intro');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _mpin = '';
          _confirmMpin = '';
          _isConfirming = false;
        });
        _showError('Could not save MPIN. Please try again.');
      }
    }
  }
   // Offers to turn on fingerprint/face unlock if the device supports it.
  /// MPIN remains the fallback either way -- this only ever makes unlock
  /// faster, never removes the MPIN path
  Future<void> _maybeEnableBiometric() async {
    final localAuth = LocalAuthentication();
    try {
      final canCheck = await localAuth.canCheckBiometrics;
      final deviceSupported = await localAuth.isDeviceSupported();
      if (!canCheck || !deviceSupported || !mounted) return;

      final wantsToEnable = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppColors.backgroundCard,
          icon: const Icon(Icons.fingerprint_rounded,
              color: AppColors.primary, size: 36),
          title: Text('Enable fingerprint unlock?',
              style: AppTextStyles.headlineSmall),
          content: Text(
            'Unlock YOUPI faster next time with your fingerprint or face '
                'instead of typing your MPIN. You can always fall back to your '
                'MPIN if it doesn\'t work.',
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Not now', style: AppTextStyles.tealLink),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Enable', style: AppTextStyles.tealLink),
            ),
          ],
        ),
      );

      if (wantsToEnable != true || !mounted) return;

      // Confirm it actually works on this device/finger before flipping the
      // flag on -- avoids locking someone out with a setting that doesn't work.
      final verified = await localAuth.authenticate(
        localizedReason: 'Confirm to enable fingerprint unlock',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (verified) {
        await StorageService.setBiometric(true);
      }
    } catch (e) {
      debugPrint('Biometric enable check failed: $e');
      // Non-fatal -- MPIN remains the unlock method either way.
    }
  }



  @override
  Widget build(BuildContext context) {
    final current = _isConfirming ? _confirmMpin : _mpin;
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(backgroundColor: AppColors.backgroundPrimary),
      body: Padding(
        padding: const EdgeInsets.all(AppDimensions.paddingPage),
        child: Column(
          children: [
            const SizedBox(height: 20),
            Text(_isConfirming ? 'Confirm MPIN' : AppStrings.mpinSetupTitle,
                style: AppTextStyles.displaySmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
                _isConfirming
                    ? 'Re-enter your 4-digit MPIN'
                    : AppStrings.mpinSetupSubtitle,
                style: AppTextStyles.bodyMedium
                    .copyWith(color: AppColors.textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 48),
            // Dot indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                  4,
                      (i) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 16,
                    height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < current.length
                          ? AppColors.primary
                          : AppColors.divider,
                      boxShadow: i < current.length
                          ? [
                        BoxShadow(
                            color: AppColors.primaryGlow,
                            blurRadius: 8)
                      ]
                          : null,
                    ),
                  )),
            ),
            const SizedBox(height: 24),
            // Loading indicator (ab _isLoading actually use hota hai)
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            const Spacer(),
            // Number pad
            for (final row in [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              ['', '0', '⌫']
            ])
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: row
                    .map((d) => GestureDetector(
                  onTap: () => d == '⌫'
                      ? _onDelete()
                      : d.isNotEmpty
                      ? _onDigit(d)
                      : null,
                  child: Container(
                    width: 80,
                    height: 72,
                    margin: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: d.isEmpty
                          ? Colors.transparent
                          : AppColors.backgroundCard,
                      borderRadius: BorderRadius.circular(12),
                      border: d.isEmpty
                          ? null
                          : Border.all(color: AppColors.divider),
                    ),
                    child: Center(
                      child: d == '⌫'
                          ? const Icon(Icons.backspace_rounded,
                          color: AppColors.textSecondary, size: 20)
                          : Text(d, style: AppTextStyles.headlineLarge),
                    ),
                  ),
                ))
                    .toList(),
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}