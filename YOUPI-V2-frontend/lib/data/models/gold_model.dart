class GoldModel {
  final double pricePerGram;
  final double priceChange; // percentage
  final bool isPriceUp;
  final DateTime lastUpdated;
  final double balanceGrams;
  final double balanceValue;

  const GoldModel({
    required this.pricePerGram,
    required this.priceChange,
    required this.isPriceUp,
    required this.lastUpdated,
    this.balanceGrams = 0,
    this.balanceValue = 0,
  });

  GoldModel copyWith({double? pricePerGram, double? priceChange, bool? isPriceUp, double? balanceGrams, double? balanceValue}) {
    return GoldModel(
      pricePerGram: pricePerGram ?? this.pricePerGram,
      priceChange: priceChange ?? this.priceChange,
      isPriceUp: isPriceUp ?? this.isPriceUp,
      lastUpdated: DateTime.now(),
      balanceGrams: balanceGrams ?? this.balanceGrams,
      balanceValue: balanceValue ?? this.balanceValue,
    );
  }
}
