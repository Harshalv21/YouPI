class GoldModel {
  final double pricePerGram; // buy rate -- kept for backward compatibility
  final double sellRatePerGram;
  final double priceChange; // percentage
  final bool isPriceUp;
  final DateTime lastUpdated;
  final double balanceGrams;
  final double balanceValue;
  final double totalInvested;

  const GoldModel({
    required this.pricePerGram,
    this.sellRatePerGram = 0,
    required this.priceChange,
    required this.isPriceUp,
    required this.lastUpdated,
    this.balanceGrams = 0,
    this.balanceValue = 0,
    this.totalInvested = 0,
  });

  GoldModel copyWith({
    double? pricePerGram,
    double? sellRatePerGram,
    double? priceChange,
    bool? isPriceUp,
    double? balanceGrams,
    double? balanceValue,
    double? totalInvested,
  }) {
    return GoldModel(
      pricePerGram: pricePerGram ?? this.pricePerGram,
      sellRatePerGram: sellRatePerGram ?? this.sellRatePerGram,
      priceChange: priceChange ?? this.priceChange,
      isPriceUp: isPriceUp ?? this.isPriceUp,
      lastUpdated: DateTime.now(),
      balanceGrams: balanceGrams ?? this.balanceGrams,
      balanceValue: balanceValue ?? this.balanceValue,
      totalInvested: totalInvested ?? this.totalInvested,
    );
  }
}