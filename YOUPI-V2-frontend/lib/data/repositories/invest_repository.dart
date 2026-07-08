import 'dart:math';
import '../datasources/mock_data.dart';
import '../models/gold_model.dart';
import '../models/loan_model.dart';

// NOTE: WalletRepository has been moved to its own file
// (wallet_repository.dart) and is now backend-connected.
// InvestRepository and BnplRepository remain mock for now — they will be
// migrated to real endpoints in a later step.

class InvestRepository {
  Future<GoldModel> getGoldPrice() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return MockData.mockGold;
  }

  GoldModel getUpdatedGoldPrice(GoldModel current) {
    final random = Random();
    final change = (random.nextDouble() - 0.5) * 0.6; // ±0.3%
    final newPrice = current.pricePerGram * (1 + change / 100);
    return current.copyWith(
      pricePerGram: newPrice,
      priceChange: change.abs(),
      isPriceUp: change >= 0,
    );
  }

  Future<bool> buyGold(double amount) async {
    await Future.delayed(const Duration(milliseconds: 1000));
    return true;
  }

  Future<bool> sellGold(double grams) async {
    await Future.delayed(const Duration(milliseconds: 1000));
    return true;
  }

  Future<double> calculateFdMaturity(
      double principal, double rate, int months) async {
    return FdModel.calculateMaturity(principal, rate, months);
  }

  Future<bool> openFd(double amount, int months) async {
    await Future.delayed(const Duration(milliseconds: 1200));
    return true;
  }
}

class BnplRepository {
  Future<bool> applyForBnpl({
    required double income,
    required String employmentType,
    required String pan,
  }) async {
    await Future.delayed(const Duration(milliseconds: 2000));
    return income >= 15000; // approve if income >= 15000
  }

  Future<bool> createSmartDeposit(double amount) async {
    await Future.delayed(const Duration(milliseconds: 1200));
    return true;
  }
}