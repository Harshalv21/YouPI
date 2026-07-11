import 'package:flutter/material.dart';
import '../../data/repositories/user_repository.dart';
import '../../data/models/user_model.dart';

class SettingsViewModel extends ChangeNotifier {
  final UserRepository _userRepo = UserRepository();

  UserModel? _user;
  bool _isLoading = false;
  String? _error;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> loadProfile() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _user = await _userRepo.getProfile();
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateProfile({String? fullName, String? email}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _user = await _userRepo.updateProfile(fullName: fullName, email: email);
      return true;
    } catch (e) {
      _error = e.toString().replaceFirst('Exception: ', '');
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}