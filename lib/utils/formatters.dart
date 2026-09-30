import 'package:intl/intl.dart';

import 'currencies.dart';

class AppFormatters {
  static final Map<String, NumberFormat> _moneyFormats = {};

  static String money(double value, {String currencyCode = 'EGP'}) {
    final currency = AppCurrencies.byCode(currencyCode);
    final formatter = _moneyFormats.putIfAbsent(
      currency.code,
      () => NumberFormat.currency(
        locale: 'en',
        symbol: currency.symbol,
        decimalDigits: currency.decimalDigits,
      ),
    );
    return formatter.format(value);
  }

  static String compactMoney(double value, {String currencyCode = 'EGP'}) {
    final symbol = AppCurrencies.byCode(currencyCode).symbol;
    if (value.abs() >= 1000000) {
      return '$symbol${(value / 1000000).toStringAsFixed(1)}M';
    }
    if (value.abs() >= 1000) {
      return '$symbol${(value / 1000).toStringAsFixed(1)}K';
    }
    return '$symbol${value.toStringAsFixed(0)}';
  }

  static String date(DateTime value) => DateFormat('d MMM yyyy').format(value);
  static String shortDate(DateTime value) => DateFormat('d MMM').format(value);
  static String month(DateTime value) => DateFormat('MMMM yyyy').format(value);
  static String weekday(DateTime value) => DateFormat('EEEE, d MMM').format(value);

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
