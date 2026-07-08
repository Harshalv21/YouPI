import 'package:flutter/material.dart';
import '../../data/repositories/auth_repository.dart';

class AuthViewModel extends ChangeNotifier {
  final AuthRepository _repo = AuthRepository();

  bool _isLoading = false;
  String? _error;
  String _mobile = '';
  String _name = '';
  String? _email;
  DateTime? _dob;
  bool _otpSent = false;
  int _otpResendCountdown = 30;

  bool get isLoading => _isLoading;
  String? get error => _error;
  String get mobile => _mobile;
  String get name => _name;
  bool get otpSent => _otpSent;
  int get otpResendCountdown => _otpResendCountdown;
  bool get isMobileValid => mobile.length == 10;

  void setMobile(String val) { _mobile = val.trim(); notifyListeners(); }
  void setName(String val) { _name = val.trim(); notifyListeners(); }
  void setEmail(String val) { _email = val.trim(); notifyListeners(); }
  void setDob(DateTime? val) { _dob = val; notifyListeners(); }

  Future<bool> sendOtp() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final ok = await _repo.sendOtp(_mobile);   // repository ko mobile pass
      _otpSent = ok;
      if (ok) _startResendTimer();
      return ok;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> verifyOtp(String otp) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      return await _repo.verifyOtp(_mobile, otp);
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _startResendTimer() {
    _otpResendCountdown = 30;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (_otpResendCountdown > 0) {
        _otpResendCountdown--;
        notifyListeners();
        return true;
      }
      return false;
    });
  }

  Future<void> resendOtp() async {
    await sendOtp();   // ab bina argument — theek
  }

  bool validateStep1() {
    if (_name.isEmpty) return false;
    if (_dob == null) return false;
    final age = DateTime.now().year - _dob!.year;
    if (age < 18) return false;
    return true;
  }
}