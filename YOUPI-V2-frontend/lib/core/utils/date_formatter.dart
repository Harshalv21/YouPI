import 'package:intl/intl.dart';

class DateFormatter {
  DateFormatter._();

  static final _ddMMYYYY = DateFormat('dd/MM/yyyy');
  static final _mmDDYYYY = DateFormat('MM/dd/yyyy');
  static final _displayDate = DateFormat('d MMM yyyy');
  static final _displayDateTime = DateFormat('d MMM yyyy, h:mm a');
  static final _timeOnly = DateFormat('h:mm a');
  static final _monthYear = DateFormat('MMM yyyy');
  static final _dayMonth = DateFormat('d MMM');
  static final _iso = DateFormat('yyyy-MM-dd');

  static String toDDMMYYYY(DateTime date) => _ddMMYYYY.format(date);
  static String toMMDDYYYY(DateTime date) => _mmDDYYYY.format(date);
  static String toDisplay(DateTime date) => _displayDate.format(date);
  static String toDisplayDateTime(DateTime date) => _displayDateTime.format(date);
  static String toTimeOnly(DateTime date) => _timeOnly.format(date);
  static String toMonthYear(DateTime date) => _monthYear.format(date);
  static String toDayMonth(DateTime date) => _dayMonth.format(date);
  static String toIso(DateTime date) => _iso.format(date);

  static DateTime? parseDisplay(String value) {
    try { return _ddMMYYYY.parse(value); } catch (_) { return null; }
  }

  static String relativeDay(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return _displayDate.format(date);
  }
}
