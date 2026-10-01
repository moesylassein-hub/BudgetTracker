// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../models/transaction.dart';

class ImportTable {
  final String fileName;
  final String? sheetName;
  final List<String> headers;
  final List<List<String>> rows;
  final bool looksLikeParagaMoneyTracker;

  const ImportTable({
    required this.fileName,
    required this.sheetName,
    required this.headers,
    required this.rows,
    required this.looksLikeParagaMoneyTracker,
  });
}

class ImportMapping {
  final int? date;
  final int? description;
  final int? category;
  final int? subCategory;
  final int? ledger;
  final int? account;
  final int? note;
  final int? amount;
  final int? incomeAmount;
  final int? expenseAmount;
  final int? type;
  final int? wallet;
  final int? currency;
  final int? labels;

  const ImportMapping({
    this.date,
    this.description,
    this.category,
    this.subCategory,
    this.ledger,
    this.account,
    this.note,
    this.amount,
    this.incomeAmount,
    this.expenseAmount,
    this.type,
    this.wallet,
    this.currency,
    this.labels,
  });

  ImportMapping copyWith({
    int? date,
    int? description,
    int? category,
    int? subCategory,
    int? ledger,
    int? account,
    int? note,
    int? amount,
    int? incomeAmount,
    int? expenseAmount,
    int? type,
    int? wallet,
    int? currency,
    int? labels,
    bool clearDate = false,
    bool clearDescription = false,
    bool clearCategory = false,
    bool clearSubCategory = false,
    bool clearLedger = false,
    bool clearAccount = false,
    bool clearNote = false,
    bool clearAmount = false,
    bool clearIncomeAmount = false,
    bool clearExpenseAmount = false,
    bool clearType = false,
    bool clearWallet = false,
    bool clearCurrency = false,
    bool clearLabels = false,
  }) {
    return ImportMapping(
      date: clearDate ? null : date ?? this.date,
      description:
          clearDescription ? null : description ?? this.description,
      category: clearCategory ? null : category ?? this.category,
      subCategory:
          clearSubCategory ? null : subCategory ?? this.subCategory,
      ledger: clearLedger ? null : ledger ?? this.ledger,
      account: clearAccount ? null : account ?? this.account,
      note: clearNote ? null : note ?? this.note,
      amount: clearAmount ? null : amount ?? this.amount,
      incomeAmount:
          clearIncomeAmount ? null : incomeAmount ?? this.incomeAmount,
      expenseAmount:
          clearExpenseAmount ? null : expenseAmount ?? this.expenseAmount,
      type: clearType ? null : type ?? this.type,
      wallet: clearWallet ? null : wallet ?? this.wallet,
      currency: clearCurrency ? null : currency ?? this.currency,
      labels: clearLabels ? null : labels ?? this.labels,
    );
  }
}

class ImportPreview {
  final List<Transaction> ready;
  final int duplicateCount;
  final int invalidCount;
  final int transferCount;
  final Set<String> sourceCurrencies;
  final List<String> warnings;

  const ImportPreview({
    required this.ready,
    required this.duplicateCount,
    required this.invalidCount,
    required this.transferCount,
    required this.sourceCurrencies,
    required this.warnings,
  });
}

class ImportService {
  const ImportService();

  ImportTable readFile({
    required String fileName,
    required Uint8List bytes,
  }) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.xlsx')) {
      return _readExcel(fileName, bytes);
    }
    if (lower.endsWith('.csv')) {
      return _readCsv(fileName, bytes);
    }
    throw const FormatException('Choose a CSV or XLSX file.');
  }

  ImportMapping detectMapping(ImportTable table) {
    int? find(List<String> aliases) {
      for (var i = 0; i < table.headers.length; i++) {
        final normalized = _normalizeHeader(table.headers[i]);
        if (aliases.contains(normalized)) return i;
      }
      for (var i = 0; i < table.headers.length; i++) {
        final normalized = _normalizeHeader(table.headers[i]);
        if (aliases.any(
          (alias) =>
              alias.length >= 4 && normalized.contains(alias),
        )) {
          return i;
        }
      }
      return null;
    }

    return ImportMapping(
      date: find(const [
        'date',
        'transactiondate',
        'datetime',
        'createddate',
        'createdat',
      ]),
      description: find(const [
        'remark',
        'remarks',
        'description',
        'merchant',
        'payee',
        'title',
        'transaction',
        'details',
        'name',
        'note',
        'notes',
      ]),
      category: find(const ['category', 'categories']),
      subCategory: find(const [
        'subcategory',
        'subcategories',
        'subcat',
      ]),
      ledger: find(const [
        'ledger',
        'ledgername',
        'book',
        'bookname',
      ]),
      account: find(const [
        'account',
        'accountname',
      ]),
      note: find(const ['note', 'notes', 'memo', 'comment', 'comments']),
      amount: find(const [
        'amount',
        'amountauto',
        'value',
        'transactionamount',
        'total',
      ]),
      incomeAmount: find(const [
        'income',
        'amountincome',
        'incomeamount',
        'credit',
        'moneyin',
        'inflow',
      ]),
      expenseAmount: find(const [
        'expense',
        'amountexpense',
        'expenseamount',
        'debit',
        'moneyout',
        'outflow',
      ]),
      type: find(const [
        'type',
        'transactiontype',
        'incomexpense',
        'incomeexpense',
      ]),
      wallet: find(const [
        'wallet',
        'walletname',
      ]),
      currency: find(const [
        'currency',
        'currencycode',
        'walletcurrency',
      ]),
      labels: find(const ['label', 'labels', 'tag', 'tags']),
    );
  }

  ImportPreview preview({
    required ImportTable table,
    required ImportMapping mapping,
    required List<Transaction> existingTransactions,
  }) {
    if (mapping.date == null) {
      throw const FormatException('Choose the Date column.');
    }
    if (mapping.amount == null &&
        mapping.incomeAmount == null &&
        mapping.expenseAmount == null) {
      throw const FormatException(
        'Choose Amount, or choose the Income / Expense amount columns.',
      );
    }

    final existingCounts = <String, int>{};
    for (final item in existingTransactions) {
      final key = _duplicateKey(item);
      existingCounts[key] = (existingCounts[key] ?? 0) + 1;
    }

    final seenImported = <String, int>{};
    final ready = <Transaction>[];
    final warnings = <String>[];
    var duplicateCount = 0;
    var invalidCount = 0;
    var transferCount = 0;
    final sourceCurrencies = <String>{};

    for (var rowIndex = 0; rowIndex < table.rows.length; rowIndex++) {
      final row = table.rows[rowIndex];
      try {
        final typeText = _cell(row, mapping.type).toLowerCase();
        final categoryText = _cell(row, mapping.category).trim();
        final subCategoryText =
            _cell(row, mapping.subCategory).trim();

        if (_looksLikeTransfer(typeText) ||
            _looksLikeTransfer(categoryText.toLowerCase())) {
          transferCount++;
          continue;
        }

        final parsedDate = _parseDate(_cell(row, mapping.date));
        if (parsedDate == null) {
          invalidCount++;
          warnings.add(
            'Row ' + (rowIndex + 2).toString() + ': date could not be read.',
          );
          continue;
        }

        final amountAndType = _resolveAmountAndType(row, mapping, typeText);
        if (amountAndType == null || amountAndType.amount <= 0) {
          invalidCount++;
          warnings.add(
            'Row ' + (rowIndex + 2).toString() + ': amount could not be read.',
          );
          continue;
        }

        var description = _cell(row, mapping.description).trim();
        if (description.isEmpty) {
          description = categoryText.isEmpty
              ? 'Imported transaction'
              : categoryText;
        }

        var category = categoryText;
        if (category.isEmpty && subCategoryText.isNotEmpty) {
          category = subCategoryText;
        }
        if (category.isEmpty) {
          category = amountAndType.type == TransactionType.income
              ? 'Other Income'
              : 'Other';
        }

        final noteParts = <String>[];
        final note = _cell(row, mapping.note).trim();
        if (note.isNotEmpty && note != description) noteParts.add(note);

        final ledger = _cell(row, mapping.ledger).trim();
        if (ledger.isNotEmpty) noteParts.add('Ledger: ' + ledger);

        final account = _cell(row, mapping.account).trim();
        if (account.isNotEmpty) noteParts.add('Account: ' + account);

        if (subCategoryText.isNotEmpty &&
            subCategoryText.toLowerCase() != category.toLowerCase()) {
          noteParts.add('Sub-category: ' + subCategoryText);
        }

        final wallet = _cell(row, mapping.wallet).trim();
        if (wallet.isNotEmpty) noteParts.add('Wallet: ' + wallet);

        final currency = _cell(row, mapping.currency).trim();
        if (currency.isNotEmpty) {
          sourceCurrencies.add(currency.toUpperCase());
          noteParts.add('Currency: ' + currency);
        }

        final labels = _cell(row, mapping.labels).trim();
        if (labels.isNotEmpty) noteParts.add('Labels: ' + labels);

        final transaction = Transaction(
          id: 'import_' +
              DateTime.now().microsecondsSinceEpoch.toString() +
              '_' +
              rowIndex.toString(),
          store: description,
          amount: amountAndType.amount,
          category: category,
          date: parsedDate,
          note: noteParts.join(' • '),
          type: amountAndType.type,
        );

        final key = _duplicateKey(transaction);
        final seen = (seenImported[key] ?? 0) + 1;
        seenImported[key] = seen;
        final existing = existingCounts[key] ?? 0;
        if (seen <= existing) {
          duplicateCount++;
          continue;
        }

        ready.add(transaction);
      } catch (_) {
        invalidCount++;
        warnings.add(
          'Row ' + (rowIndex + 2).toString() + ': could not be imported.',
        );
      }
    }

    return ImportPreview(
      ready: ready,
      duplicateCount: duplicateCount,
      invalidCount: invalidCount,
      transferCount: transferCount,
      sourceCurrencies: sourceCurrencies,
      warnings: warnings,
    );
  }

  ImportTable _readCsv(String fileName, Uint8List bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('\ufeff')) text = text.substring(1);
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    final firstLine = text
        .split('\n')
        .firstWhere(
          (line) => line.trim().isNotEmpty,
          orElse: () => '',
        );
    final delimiter = _detectDelimiter(firstLine);

    final rows = CsvToListConverter(
      fieldDelimiter: delimiter,
      eol: '\n',
      shouldParseNumbers: false,
    ).convert(text);

    return _tableFromRows(
      fileName: fileName,
      sheetName: null,
      rawRows: rows,
    );
  }

  ImportTable _readExcel(String fileName, Uint8List bytes) {
    final workbook = Excel.decodeBytes(bytes);
    ImportTable? fallback;

    for (final entry in workbook.tables.entries) {
      final sheet = entry.value;
      if (sheet.rows.isEmpty) continue;
      final rawRows = sheet.rows
          .map(
            (row) => row
                .map((cell) => _excelCellToString(cell?.value))
                .toList(),
          )
          .toList();

      try {
        final table = _tableFromRows(
          fileName: fileName,
          sheetName: entry.key,
          rawRows: rawRows,
        );
        fallback ??= table;
        final mapping = detectMapping(table);
        final hasAmount = mapping.amount != null ||
            mapping.incomeAmount != null ||
            mapping.expenseAmount != null;
        if (mapping.date != null && hasAmount) return table;
      } catch (_) {
        // Ignore non-tabular/summary sheets and continue looking.
      }
    }

    if (fallback != null) return fallback;
    throw const FormatException('No transaction table was found in the XLSX.');
  }

  ImportTable _tableFromRows({
    required String fileName,
    required String? sheetName,
    required List<List<dynamic>> rawRows,
  }) {
    final rows = rawRows
        .map(
          (row) => row.map((value) => value?.toString().trim() ?? '').toList(),
        )
        .where((row) => row.any((cell) => cell.isNotEmpty))
        .toList();

    if (rows.length < 2) {
      throw const FormatException(
        'The file needs a header row and at least one transaction.',
      );
    }

    var headerIndex = 0;
    for (var i = 0; i < rows.length && i < 20; i++) {
      final normalized = rows[i].map(_normalizeHeader).toSet();
      final hasDate = normalized.any(
        (value) => value == 'date' || value == 'transactiondate',
      );
      final hasAmount = normalized.any(
        (value) =>
            value == 'amount' ||
            value == 'amountauto' ||
            value == 'income' ||
            value == 'expense' ||
            value == 'amountincome' ||
            value == 'amountexpense',
      );
      if (hasDate && hasAmount) {
        headerIndex = i;
        break;
      }
    }

    final headers = rows[headerIndex];
    final width = headers.length;
    final amountIndex = headers.indexWhere(
      (header) {
        final normalized = _normalizeHeader(header);
        return normalized == 'amount' ||
            normalized == 'amountauto' ||
            normalized == 'transactionamount';
      },
    );

    final dataRows = rows.skip(headerIndex + 1).map((row) {
      var normalizedRow = List<String>.from(row);

      // Some finance apps export values such as £4,233.33 without quoting
      // the thousands comma. CSV then sees one extra field and shifts every
      // later column. Rejoin the overflow back into the Amount cell.
      if (amountIndex >= 0 && normalizedRow.length > width) {
        final overflow = normalizedRow.length - width;
        final amountEnd = amountIndex + overflow;
        if (amountEnd < normalizedRow.length) {
          normalizedRow = [
            ...normalizedRow.take(amountIndex),
            normalizedRow
                .sublist(amountIndex, amountEnd + 1)
                .join(','),
            ...normalizedRow.skip(amountEnd + 1),
          ];
        }
      }

      if (normalizedRow.length > width) {
        normalizedRow = normalizedRow.take(width).toList();
      }
      if (normalizedRow.length < width) {
        normalizedRow = [
          ...normalizedRow,
          ...List.filled(width - normalizedRow.length, ''),
        ];
      }
      return normalizedRow;
    }).where((row) => row.any((cell) => cell.isNotEmpty)).toList();

    if (dataRows.isEmpty) {
      throw const FormatException(
        'The file has headers but no transaction rows.',
      );
    }

    final normalized = headers.map(_normalizeHeader).toSet();
    final looksLikeParaga =
        normalized.contains('date') &&
        normalized.contains('category') &&
        (normalized.contains('remark') ||
            normalized.contains('remarks') ||
            normalized.contains('description')) &&
        (normalized.contains('amount') ||
            normalized.contains('income') ||
            normalized.contains('expense') ||
            normalized.contains('amountincome') ||
            normalized.contains('amountexpense'));

    return ImportTable(
      fileName: fileName,
      sheetName: sheetName,
      headers: headers,
      rows: dataRows,
      looksLikeParagaMoneyTracker: looksLikeParaga,
    );
  }

  _AmountAndType? _resolveAmountAndType(
    List<String> row,
    ImportMapping mapping,
    String typeText,
  ) {
    final income = _parseAmount(_cell(row, mapping.incomeAmount));
    final expense = _parseAmount(_cell(row, mapping.expenseAmount));

    if (income != null && income.abs() > 0) {
      return _AmountAndType(income.abs(), TransactionType.income);
    }
    if (expense != null && expense.abs() > 0) {
      return _AmountAndType(expense.abs(), TransactionType.expense);
    }

    final signed = _parseAmount(_cell(row, mapping.amount));
    if (signed == null || signed == 0) return null;

    final explicitType = _parseType(typeText);
    if (explicitType != null) {
      return _AmountAndType(signed.abs(), explicitType);
    }

    // Money Tracker (Paraga) documents Amount(Auto) as using negative values
    // for expenses and positive values for income.
    return _AmountAndType(
      signed.abs(),
      signed < 0 ? TransactionType.expense : TransactionType.income,
    );
  }

  TransactionType? _parseType(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.contains('expense') ||
        normalized == 'debit' ||
        normalized == 'out') {
      return TransactionType.expense;
    }
    if (normalized.contains('income') ||
        normalized == 'credit' ||
        normalized == 'in') {
      return TransactionType.income;
    }
    return null;
  }

  bool _looksLikeTransfer(String value) {
    final normalized = value.replaceAll(RegExp(r'[^a-z]'), '');
    return normalized.contains('transfer');
  }

  DateTime? _parseDate(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;

    final iso = DateTime.tryParse(value);
    if (iso != null) return iso;

    final cleaned = value
        .replaceAll(RegExp(r'\s+\d{1,2}:\d{2}(:\d{2})?.*$'), '')
        .trim();

    const formats = [
      'dd-MMM-yyyy',
      'MMM-dd-yyyy',
      'yyyy-MMM-dd',
      'dd/MMM/yyyy',
      'MMM/dd/yyyy',
      'yyyy/MMM/dd',
      'dd-MM-yyyy',
      'MM-dd-yyyy',
      'yyyy-MM-dd',
      'dd/MM/yyyy',
      'MM/dd/yyyy',
      'yyyy/MM/dd',
      'd-MMM-yyyy',
      'MMM-d-yyyy',
      'd/MMM/yyyy',
      'MMM/d/yyyy',
      'd-M-yyyy',
      'M-d-yyyy',
      'd/M/yyyy',
      'M/d/yyyy',
      'yyyy-M-d',
      'yyyy/M/d',
    ];

    for (final pattern in formats) {
      try {
        return DateFormat(pattern, 'en_US').parseStrict(cleaned);
      } catch (_) {
        // Try the next documented/common format.
      }
    }
    return null;
  }

  double? _parseAmount(String raw) {
    var value = raw.trim();
    if (value.isEmpty || value == '-' || value == '—') return null;

    var negative = false;
    if (value.startsWith('(') && value.endsWith(')')) {
      negative = true;
      value = value.substring(1, value.length - 1);
    }

    value = value.replaceAll(RegExp(r'[^\d,\.\-+]'), '');
    if (value.isEmpty) return null;

    final comma = value.lastIndexOf(',');
    final dot = value.lastIndexOf('.');
    if (comma >= 0 && dot >= 0) {
      if (comma > dot) {
        value = value.replaceAll('.', '').replaceAll(',', '.');
      } else {
        value = value.replaceAll(',', '');
      }
    } else if (comma >= 0) {
      final decimals = value.length - comma - 1;
      if (decimals == 1 || decimals == 2 || decimals == 3) {
        value = value.replaceAll(',', '.');
      } else {
        value = value.replaceAll(',', '');
      }
    }

    final parsed = double.tryParse(value);
    if (parsed == null) return null;
    return negative ? -parsed.abs() : parsed;
  }

  String _excelCellToString(CellValue? value) {
    if (value == null) return '';
    if (value is DateCellValue) {
      return value.asDateTimeLocal().toIso8601String();
    }
    if (value is DateTimeCellValue) {
      return value.asDateTimeLocal().toIso8601String();
    }
    return value.toString();
  }

  String _cell(List<String> row, int? index) {
    if (index == null || index < 0 || index >= row.length) return '';
    return row[index];
  }

  String _detectDelimiter(String headerLine) {
    final counts = <String, int>{
      ',': ','.allMatches(headerLine).length,
      ';': ';'.allMatches(headerLine).length,
      '\t': '\t'.allMatches(headerLine).length,
    };
    return counts.entries.reduce(
      (a, b) => a.value >= b.value ? a : b,
    ).key;
  }

  String _normalizeHeader(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('&', 'and')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');

  String _duplicateKey(Transaction item) {
    final day =
        item.date.year.toString().padLeft(4, '0') +
        '-' +
        item.date.month.toString().padLeft(2, '0') +
        '-' +
        item.date.day.toString().padLeft(2, '0');
    String normalize(String value) =>
        value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    return [
      day,
      item.type.name,
      item.amount.toStringAsFixed(4),
      normalize(item.store),
      normalize(item.category),
    ].join('|');
  }
}

class _AmountAndType {
  final double amount;
  final TransactionType type;

  const _AmountAndType(this.amount, this.type);
}
