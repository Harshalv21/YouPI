import 'package:flutter/material.dart';

class OnboardingViewModel extends ChangeNotifier {
  int _currentPage = 0;
  int get currentPage => _currentPage;
  int get totalPages => 3;
  bool get isLastPage => _currentPage == totalPages - 1;

  void nextPage() {
    if (_currentPage < totalPages - 1) {
      _currentPage++;
      notifyListeners();
    }
  }

  void setPage(int index) {
    _currentPage = index;
    notifyListeners();
  }
}
