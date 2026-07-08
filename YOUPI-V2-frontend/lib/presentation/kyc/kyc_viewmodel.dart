import 'package:flutter/material.dart';
import '../../core/services/storage_service.dart';

class KycViewModel extends ChangeNotifier {
  bool _isLoading = false;
  String? _error;
  String _aadhaar = '';
  String _pan = '';
  bool _aadhaarOtpSent = false;
  bool _panVerified = false;
  bool _selfieCapture = false;
  int _aadhaarCountdown = 24;

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get aadhaarOtpSent => _aadhaarOtpSent;
  bool get panVerified => _panVerified;
  bool get selfieCapture => _selfieCapture;
  int get aadhaarCountdown => _aadhaarCountdown;
  String get pan => _pan;

  void setAadhaar(String v) { _aadhaar = v; notifyListeners(); }
  void setPan(String v) {
    _pan = v.toUpperCase();
    _panVerified = _isValidPan(_pan);
    notifyListeners();
  }

  bool _isValidPan(String pan) =>
      RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(pan);

  Future<void> sendAadhaarOtp() async {
    _isLoading = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 1000));
    _aadhaarOtpSent = true;
    _isLoading = false;
    _startCountdown();
    notifyListeners();
  }

  void _startCountdown() {
    _aadhaarCountdown = 24;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (_aadhaarCountdown > 0) {
        _aadhaarCountdown--;
        notifyListeners();
        return true;
      }
      return false;
    });
  }

  Future<bool> verifyAadhaar(String otp) async {
    _isLoading = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 1200));
    _isLoading = false;
    notifyListeners();
    return otp.length == 6;
  }

  Future<void> captureSelfie() async {
    _selfieCapture = true;
    notifyListeners();
  }

  Future<bool> completeKyc() async {
    _isLoading = true;
    notifyListeners();
    await Future.delayed(const Duration(milliseconds: 1500));
    await StorageService.setKycStatus('verified');
    _isLoading = false;
    notifyListeners();
    return true;
  }
}
