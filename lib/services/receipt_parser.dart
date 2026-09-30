import 'package:intl/intl.dart';

import '../models/receipt_scan_result.dart';

class ReceiptParser {
  static final _fallbackMoneyRegex = RegExp(
    r'(?<!\d)(\d{1,7}(?:[,.]\d{2}))(?!\d)',
  );
  static final _labelledMoneyRegex = RegExp(
    r'(?<!\d)(\d{1,3}(?:[ ,.]\d{3})+(?:[.,]\d{1,2})?|\d{1,7}(?:[.,]\d{1,2})?)(?!\d)',
  );
  static final _datePatterns = <RegExp>[
    RegExp(r'\b(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{2,4})\b'),
    RegExp(r'\b(\d{4})[/.\-](\d{1,2})[/.\-](\d{1,2})\b'),
  ];

  ReceiptScanResult parse(String text) {
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final store = _merchant(lines);
    final amount = _total(lines);
    final category = _category(text);
    final date = _date(text, lines);
    final currency = _currency(text);
    final tax = _tax(lines);
    final receiptNumber = _receiptNumber(lines);

    var confidence = 0.0;
    if (store != 'Receipt purchase') confidence += 0.25;
    if (amount != null) confidence += 0.35;
    if (date != null) confidence += 0.15;
    if (currency != null) confidence += 0.1;
    if (tax != null) confidence += 0.05;
    if (category != 'Other') confidence += 0.1;

    return ReceiptScanResult(
      store: store,
      amount: amount,
      category: category,
      date: date,
      rawText: text,
      taxAmount: tax,
      currencyCode: currency,
      receiptNumber: receiptNumber,
      confidence: confidence.clamp(0.0, 1.0).toDouble(),
    );
  }

  String _merchant(List<String> lines) {
    for (final line in lines.take(8)) {
      final lower = line.toLowerCase();
      final hasLetters = RegExp(r'[a-zA-Z]').hasMatch(line);
      final looksLikeMeta = lower.contains('receipt') ||
          lower.contains('invoice') ||
          lower.contains('tax') ||
          lower.contains('tel') ||
          lower.contains('vat') ||
          lower.contains('date') ||
          lower.contains('cashier') ||
          lower.contains('branch') ||
          lower.contains('www.') ||
          lower.contains('@');
      if (hasLetters && !looksLikeMeta && line.length >= 3 && line.length <= 50) {
        return _titleCase(line.replaceAll(RegExp(r'\s+'), ' '));
      }
    }
    return 'Receipt purchase';
  }

  double? _total(List<String> lines) {
    const priorityWords = [
      'grand total',
      'amount due',
      'total due',
      'net total',
      'total amount',
      'total',
      'amount',
    ];

    for (final keyword in priorityWords) {
      for (final line in lines.reversed) {
        final lower = line.toLowerCase();
        if (!lower.contains(keyword)) continue;
        if (lower.contains('subtotal') && keyword == 'total') continue;
        if (_isTenderLine(lower) && !lower.contains('amount due')) continue;
        final values = _numbers(line, allowWholeNumbers: true);
        if (values.isNotEmpty) return values.last;
      }
    }

    final candidates = <double>[];
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (_isTenderLine(lower) || lower.contains('phone') || lower.contains('tel')) {
        continue;
      }
      candidates.addAll(_numbers(line));
    }
    if (candidates.isEmpty) return null;
    candidates.sort();
    return candidates.last;
  }

  bool _isTenderLine(String lower) {
    return lower.contains('cash') ||
        lower.contains('change') ||
        lower.contains('tender') ||
        lower.contains('paid') ||
        lower.contains('visa') ||
        lower.contains('mastercard');
  }

  double? _tax(List<String> lines) {
    for (final line in lines.reversed) {
      final lower = line.toLowerCase();
      if (!(lower.contains('vat') || lower.contains('tax'))) continue;
      if (lower.contains('tax id') || lower.contains('vat no')) continue;
      final values = _numbers(line, allowWholeNumbers: true);
      if (values.isNotEmpty) return values.last;
    }
    return null;
  }

  String? _receiptNumber(List<String> lines) {
    final pattern = RegExp(
      r'(?:receipt|invoice|transaction|trx)\s*(?:no|number|#|:)\.?\s*([A-Z0-9\-]{3,24})',
      caseSensitive: false,
    );
    for (final line in lines.take(20)) {
      final match = pattern.firstMatch(line);
      if (match != null) return match.group(1);
    }
    return null;
  }

  String? _currency(String text) {
    final upper = text.toUpperCase();
    if (RegExp(r'\bEGP\b|\bL\.E\.?\b|\bLE\b').hasMatch(upper)) return 'EGP';
    if (RegExp(r'\bUSD\b').hasMatch(upper) || text.contains(r'$')) return 'USD';
    if (RegExp(r'\bEUR\b').hasMatch(upper) || text.contains('€')) return 'EUR';
    if (RegExp(r'\bSAR\b').hasMatch(upper)) return 'SAR';
    if (RegExp(r'\bAED\b').hasMatch(upper)) return 'AED';
    if (RegExp(r'\bGBP\b').hasMatch(upper) || text.contains('£')) return 'GBP';
    if (RegExp(r'\bKWD\b').hasMatch(upper)) return 'KWD';
    return null;
  }

  List<double> _numbers(String line, {bool allowWholeNumbers = false}) {
    final regex = allowWholeNumbers ? _labelledMoneyRegex : _fallbackMoneyRegex;
    return regex
        .allMatches(line)
        .map((match) => match.group(1)!)
        .map(_parseMoney)
        .whereType<double>()
        .where((value) => value > 0 && value < 10000000)
        .toList();
  }

  double? _parseMoney(String raw) {
    var value = raw.replaceAll(' ', '');
    final comma = value.lastIndexOf(',');
    final dot = value.lastIndexOf('.');

    if (comma != -1 && dot != -1) {
      if (comma > dot) {
        value = value.replaceAll('.', '').replaceAll(',', '.');
      } else {
        value = value.replaceAll(',', '');
      }
    } else if (comma != -1) {
      final digitsAfter = value.length - comma - 1;
      value = digitsAfter == 3 ? value.replaceAll(',', '') : value.replaceAll(',', '.');
    } else if (dot != -1) {
      final digitsAfter = value.length - dot - 1;
      if (digitsAfter == 3 && value.indexOf('.') == dot) {
        value = value.replaceAll('.', '');
      }
    }

    return double.tryParse(value);
  }

  DateTime? _date(String text, List<String> lines) {
    for (var i = 0; i < _datePatterns.length; i++) {
      final match = _datePatterns[i].firstMatch(text);
      if (match == null) continue;
      try {
        late int year;
        late int month;
        late int day;
        if (i == 0) {
          day = int.parse(match.group(1)!);
          month = int.parse(match.group(2)!);
          year = int.parse(match.group(3)!);
          if (year < 100) year += 2000;
        } else {
          year = int.parse(match.group(1)!);
          month = int.parse(match.group(2)!);
          day = int.parse(match.group(3)!);
        }
        final parsed = DateTime(year, month, day);
        if (parsed.year == year && parsed.month == month && parsed.day == day) {
          return parsed;
        }
      } catch (_) {
        continue;
      }
    }

    final formats = [
      DateFormat('d MMM yyyy', 'en'),
      DateFormat('dd MMM yyyy', 'en'),
      DateFormat('MMM d yyyy', 'en'),
      DateFormat('MMM dd yyyy', 'en'),
    ];
    for (final line in lines) {
      final cleaned = line.replaceAll(RegExp(r'[,]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
      for (final format in formats) {
        try {
          final parsed = format.parseStrict(cleaned);
          if (parsed.year >= 2000 && parsed.year <= DateTime.now().year + 1) return parsed;
        } catch (_) {
          // Try the next common date format.
        }
      }
    }
    return null;
  }

  String _category(String text) {
    final lower = text.toLowerCase();
    if (_containsAny(lower, [
      'restaurant', 'cafe', 'coffee', 'pizza', 'burger', 'market', 'grocery',
      'carrefour', 'hypermarket', 'bakery', 'food', 'supermarket',
    ])) {
      return 'Food';
    }
    if (_containsAny(lower, [
      'uber', 'careem', 'taxi', 'fuel', 'petrol', 'gas station', 'shell', 'mobil',
    ])) {
      return 'Transport';
    }
    if (_containsAny(lower, ['pharmacy', 'clinic', 'medical', 'hospital', 'doctor'])) {
      return 'Health';
    }
    if (_containsAny(lower, ['cinema', 'movie', 'game', 'entertainment', 'netflix'])) {
      return 'Entertainment';
    }
    if (_containsAny(lower, [
      'electricity', 'water bill', 'internet', 'telecom', 'mobile bill', 'utility',
    ])) {
      return 'Bills';
    }
    if (_containsAny(lower, ['school', 'university', 'bookstore', 'course', 'academy'])) {
      return 'Education';
    }
    if (_containsAny(lower, ['mall', 'fashion', 'clothing', 'store', 'shop', 'zara', 'h&m'])) {
      return 'Shopping';
    }
    return 'Other';
  }

  bool _containsAny(String text, List<String> terms) => terms.any(text.contains);

  String _titleCase(String value) {
    return value
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          if (word.length <= 3 && word == word.toUpperCase()) return word;
          return '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}';
        })
        .join(' ');
  }
}
