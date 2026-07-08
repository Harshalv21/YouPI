import 'package:intl/intl.dart';

class CurrencyFormatter {
  CurrencyFormatter._();

  static final _inrFormatter = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  static final _inrFormatterNoDecimal = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  static final _compactFormatter = NumberFormat.compactCurrency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 1,
  );

  static String format(double amount) => _inrFormatter.format(amount);

  static String formatNoDecimal(double amount) =>
      _inrFormatterNoDecimal.format(amount);

  static String formatCompact(double amount) =>
      _compactFormatter.format(amount);

  static String formatGrams(double grams) =>
      '${grams.toStringAsFixed(3)} gm';

  static String formatPercent(double value) =>
      '${value.toStringAsFixed(1)}%';
}
