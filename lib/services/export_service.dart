import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/transaction.dart';
import '../utils/budget_cycle.dart';

class ExportService {
  const ExportService();
  static const _excelMime =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  Future<void> shareCsv({
    required List<Transaction> transactions,
    required String currencyCode,
    required int budgetCycleStartDay,
  }) async {
    final rows = <List<String>>[
      [
        'Date',
        'Time',
        'Type',
        'Merchant',
        'Category',
        'Ledger',
        'Account',
        'Amount',
        'Currency',
        'Note',
        'Budget cycle',
      ],
      ...transactions.map(
        (item) => _row(
          item,
          currencyCode: currencyCode,
          budgetCycleStartDay: budgetCycleStartDay,
        ),
      ),
    ];

    final csv = rows.map((row) => row.map(_escapeCsv).join(',')).join('\r\n');
    final bytes = Uint8List.fromList(utf8.encode('\ufeff$csv'));
    final fileName = 'budget_tracker_${_fileStamp(DateTime.now())}.csv';

    await SharePlus.instance.share(
      ShareParams(
        title: 'Export Budget Tracker CSV',
        subject: 'Budget Tracker transactions',
        text: 'Budget Tracker transaction export',
        files: [
          XFile.fromData(bytes, mimeType: 'text/csv'),
        ],
        fileNameOverrides: [fileName],
      ),
    );
  }

  Future<void> shareExcel({
    required List<Transaction> transactions,
    required String currencyCode,
    required int budgetCycleStartDay,
  }) async {
    final workbook = Excel.createExcel();
    final defaultSheet = workbook.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'Transactions') {
      workbook.rename(defaultSheet, 'Transactions');
    }

    final transactionsSheet = workbook['Transactions'];
    transactionsSheet.appendRow([
      TextCellValue('Date'),
      TextCellValue('Time'),
      TextCellValue('Type'),
      TextCellValue('Merchant'),
      TextCellValue('Category'),
      TextCellValue('Ledger'),
      TextCellValue('Account'),
      TextCellValue('Amount'),
      TextCellValue('Currency'),
      TextCellValue('Note'),
      TextCellValue('Budget cycle'),
    ]);

    for (final item in transactions) {
      final cycleStart = BudgetCycle.startFor(item.date, budgetCycleStartDay);
      final cycleEnd = BudgetCycle.endExclusiveFor(
        item.date,
        budgetCycleStartDay,
      ).subtract(const Duration(days: 1));

      transactionsSheet.appendRow([
        TextCellValue(DateFormat('yyyy-MM-dd').format(item.date)),
        TextCellValue(DateFormat('HH:mm').format(item.date)),
        TextCellValue(item.type.label),
        TextCellValue(item.store),
        TextCellValue(item.category),
        TextCellValue(item.ledger),
        TextCellValue(item.account),
        DoubleCellValue(item.amount),
        TextCellValue(
          item.currencyCode.isEmpty ? currencyCode : item.currencyCode,
        ),
        TextCellValue(item.note),
        TextCellValue(
          '${DateFormat('yyyy-MM-dd').format(cycleStart)} - '
          '${DateFormat('yyyy-MM-dd').format(cycleEnd)}',
        ),
      ]);
    }

    transactionsSheet.setColumnWidth(0, 14);
    transactionsSheet.setColumnWidth(1, 10);
    transactionsSheet.setColumnWidth(2, 12);
    transactionsSheet.setColumnWidth(3, 28);
    transactionsSheet.setColumnWidth(4, 20);
    transactionsSheet.setColumnWidth(5, 18);
    transactionsSheet.setColumnWidth(6, 18);
    transactionsSheet.setColumnWidth(7, 14);
    transactionsSheet.setColumnWidth(8, 12);
    transactionsSheet.setColumnWidth(9, 34);
    transactionsSheet.setColumnWidth(10, 26);

    final totalIncome = transactions
        .where((item) => item.isIncome)
        .fold<double>(0, (sum, item) => sum + item.amount);
    final totalExpenses = transactions
        .where((item) => item.isExpense)
        .fold<double>(0, (sum, item) => sum + item.amount);

    final summary = workbook['Summary'];
    summary.appendRow([
      TextCellValue('Budget Tracker export'),
      TextCellValue('Value'),
    ]);
    summary.appendRow([
      TextCellValue('Generated'),
      TextCellValue(DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())),
    ]);
    summary.appendRow([
      TextCellValue('Currency'),
      TextCellValue(currencyCode),
    ]);
    summary.appendRow([
      TextCellValue('Transactions'),
      IntCellValue(transactions.length),
    ]);
    summary.appendRow([
      TextCellValue('Total income'),
      DoubleCellValue(totalIncome),
    ]);
    summary.appendRow([
      TextCellValue('Total expenses'),
      DoubleCellValue(totalExpenses),
    ]);
    summary.appendRow([
      TextCellValue('Net'),
      DoubleCellValue(totalIncome - totalExpenses),
    ]);
    summary.appendRow([
      TextCellValue('Budget cycle start day'),
      IntCellValue(budgetCycleStartDay),
    ]);
    summary.setColumnWidth(0, 28);
    summary.setColumnWidth(1, 24);

    final encoded = workbook.encode();
    if (encoded == null) {
      throw StateError('Could not create the Excel workbook.');
    }

    final bytes = Uint8List.fromList(encoded);
    final fileName = 'budget_tracker_${_fileStamp(DateTime.now())}.xlsx';

    await SharePlus.instance.share(
      ShareParams(
        title: 'Export Budget Tracker Excel',
        subject: 'Budget Tracker transactions',
        text: 'Budget Tracker Excel export',
        files: [
          XFile.fromData(bytes, mimeType: _excelMime),
        ],
        fileNameOverrides: [fileName],
      ),
    );
  }

  List<String> _row(
    Transaction item, {
    required String currencyCode,
    required int budgetCycleStartDay,
  }) {
    final cycleStart = BudgetCycle.startFor(item.date, budgetCycleStartDay);
    final cycleEnd = BudgetCycle.endExclusiveFor(
      item.date,
      budgetCycleStartDay,
    ).subtract(const Duration(days: 1));
    return [
      DateFormat('yyyy-MM-dd').format(item.date),
      DateFormat('HH:mm').format(item.date),
      item.type.label,
      item.store,
      item.category,
      item.ledger,
      item.account,
      item.amount.toStringAsFixed(2),
      item.currencyCode.isEmpty ? currencyCode : item.currencyCode,
      item.note,
      '${DateFormat('yyyy-MM-dd').format(cycleStart)} - '
          '${DateFormat('yyyy-MM-dd').format(cycleEnd)}',
    ];
  }

  String _escapeCsv(String value) {
    final escaped = value.replaceAll('"', '""');
    if (escaped.contains(',') ||
        escaped.contains('"') ||
        escaped.contains('\n') ||
        escaped.contains('\r')) {
      return '"$escaped"';
    }
    return escaped;
  }

  String _fileStamp(DateTime value) =>
      DateFormat('yyyyMMdd_HHmm').format(value);
}
