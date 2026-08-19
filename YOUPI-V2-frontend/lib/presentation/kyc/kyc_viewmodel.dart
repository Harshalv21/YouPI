import 'package:flutter/material.dart';
import '../../core/services/storage_service.dart';
import '../../data/repositories/user_repository.dart';

class KycViewModel extends ChangeNotifier {
  final UserRepository _userRepo = UserRepository();

  bool _isLoading = false;
  String? _error;
  String _aadhaar = '';
  String _pan = '';
  bool _aadhaarOtpSent = false;
  bool _selfieCapture = false;
  int _aadhaarCountdown = 24;

  // ── PAN (now backend-verified via Eko, not just regex) ──
  bool _panVerified = false;
  String? _panHolderName;
  String? _panError;

  // ── Bank account (NEW — backend-verified via Eko) ──
  String _bankAccountNumber = '';
  String _bankIfsc = '';
  bool _bankVerified = false;
  String? _bankAccountHolderName;
  String? _bankName;
  String? _bankError;

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get aadhaarOtpSent => _aadhaarOtpSent;
  bool get panVerified => _panVerified;
  String? get panHolderName => _panHolderName;
  String? get panError => _panError;
  bool get selfieCapture => _selfieCapture;
  int get aadhaarCountdown => _aadhaarCountdown;
  String get aadhaar => _aadhaar;
  String get pan => _pan;

  String get bankAccountNumber => _bankAccountNumber;
  String get bankIfsc => _bankIfsc;
  bool get bankVerified => _bankVerified;
  String? get bankAccountHolderName => _bankAccountHolderName;
  String? get bankName => _bankName;
  String? get bankError => _bankError;

  void setAadhaar(String v) { _aadhaar = v; notifyListeners(); }

  /// Just updates the raw text + resets any stale "verified" state from a
  /// previous PAN -- does NOT verify. Call verifyPanWithBackend() for that.
  void setPan(String v) {
    _pan = v.toUpperCase();
    _panVerified = false;
    _panHolderName = null;
    _panError = null;
    notifyListeners();
  }

  bool get isPanFormatValid => RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(_pan);

  /// Calls the real backend (Eko fetch-pan under the hood). Sets
  /// panVerified + panHolderName on success, panError on failure.
  Future<bool> verifyPanWithBackend() async {
    if (!isPanFormatValid) {
      _panError = 'Enter a valid PAN (e.g. ABCDE1234F)';
      notifyListeners();
      return false;
    }
    _isLoading = true;
    _panError = null;
    notifyListeners();
    try {
      final result = await _userRepo.verifyPan(_pan);
      _panVerified = result.verified;
      _panHolderName = result.nameOnPan;
      if (!result.verified) {
        _panError = 'PAN could not be verified. Please check and try again.';
      }
      return result.verified;
    } catch (e) {
      _panError = 'PAN verification failed. Please try again.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void setBankAccountNumber(String v) {
    _bankAccountNumber = v;
    _bankVerified = false;
    _bankAccountHolderName = null;
    _bankError = null;
    notifyListeners();
  }

  void setBankIfsc(String v) {
    _bankIfsc = v.toUpperCase();
    _bankVerified = false;
    _bankAccountHolderName = null;
    _bankError = null;
    notifyListeners();
  }

  bool get isBankFormatValid =>
      RegExp(r'^\d{9,18}$').hasMatch(_bankAccountNumber) &&
          RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch(_bankIfsc);

  /// Calls the real backend (Eko bank-account/sync under the hood).
  Future<bool> verifyBankAccountWithBackend() async {
    if (!isBankFormatValid) {
      _bankError = 'Enter a valid account number and IFSC';
      notifyListeners();
      return false;
    }
    _isLoading = true;
    _bankError = null;
    notifyListeners();
    try {
      final result = await _userRepo.verifyBankAccount(
        accountNumber: _bankAccountNumber,
        ifsc: _bankIfsc,
      );
      _bankVerified = result.verified;
      _bankAccountHolderName = result.accountHolderName;
      _bankName = result.bankName;
      if (!result.verified) {
        _bankError = 'Bank account could not be verified. Please check and try again.';
      }
      return result.verified;
    } catch (e) {
      _bankError = 'Bank verification failed. Please try again.';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

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

  // TODO: still a stub (Aadhaar/Digio integration unchanged, out of scope
  // for the Eko PAN + bank account work).
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