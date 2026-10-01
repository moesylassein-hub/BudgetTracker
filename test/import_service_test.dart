import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:budget_tracker/models/transaction.dart';
import 'package:budget_tracker/services/import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = ImportService();

  group('Refund imports', () {
    test(
        'explicit types preserve signs and duplicate detection distinguishes refunds',
        () {
      final table = service.readFile(
        fileName: 'refunds.csv',
        bytes: Uint8List.fromList(
          utf8.encode(
            'Date,Type,Merchant,Category,Amount\n'
            '2026-10-01,Expense,Travel,Travel,800\n'
            '2026-10-01,Expense,Travel,Travel,-800\n'
            '2026-10-01,Expense,Travel,Travel,-800\n'
            '2026-10-01,Income,Salary,Salary,-800\n'
            '2026-10-01,Expense,Travel,Travel,0\n'
            '2026-10-01,Expense,Travel,Travel,NaN\n'
            '2026-10-01,Expense,Travel,Travel,Infinity\n',
          ),
        ),
      );
      final mapping = service.detectMapping(table);
      final first = service.preview(
        table: table,
        mapping: mapping,
        existingTransactions: const [],
      );
      expect(first.ready.map((item) => item.amount), [800, -800, -800]);
      expect(first.invalidCount, 4);
      final second = service.preview(
        table: table,
        mapping: mapping,
        existingTransactions: [first.ready[1]],
      );
      expect(second.duplicateCount, 1);
      expect(second.ready.map((item) => item.amount), [800, -800]);
      expect(second.ready.every((item) => item.isExpense), isTrue);
    });

    test('split expense column preserves refund signs', () {
      final table = service.readFile(
        fileName: 'refunds.csv',
        bytes: Uint8List.fromList(
          utf8.encode(
            'Date,Category,Remark,Income,Expense\n'
            '2026-10-01,Travel,Refund,,-80\n',
          ),
        ),
      );
      final preview = service.preview(
        table: table,
        mapping: service.detectMapping(table),
        existingTransactions: const [],
      );
      expect(preview.ready.single.amount, -80);
      expect(preview.ready.single.isExpense, isTrue);
    });
  });

  group('Money Tracker file decoding', () {
    test('reads Paraga-style CSV bytes', () {
      final bytes = Uint8List.fromList(
        utf8.encode(
          'Date,Category,Remark,Amount\r\n'
          '25-09-2026,Salary,Salary,15000\r\n'
          '26-09-2026,Food,Lunch,-100\r\n',
        ),
      );

      final table = service.readFile(
        fileName: 'money_tracker.csv',
        bytes: bytes,
      );

      expect(table.looksLikeParagaMoneyTracker, isTrue);
      expect(table.rows, hasLength(2));
      expect(service.detectMapping(table).amount, 3);
    });

    test('reads Paraga-style XLSX bytes', () {
      final workbook = Excel.createExcel();
      final defaultSheet = workbook.getDefaultSheet();
      if (defaultSheet != null && defaultSheet != 'Transactions') {
        workbook.rename(defaultSheet, 'Transactions');
      }
      final sheet = workbook['Transactions'];
      sheet.appendRow([
        TextCellValue('Date'),
        TextCellValue('Category'),
        TextCellValue('Remark'),
        TextCellValue('Income'),
        TextCellValue('Expense'),
      ]);
      sheet.appendRow([
        TextCellValue('2026-09-25'),
        TextCellValue('Salary'),
        TextCellValue('Salary'),
        DoubleCellValue(15000),
        TextCellValue(''),
      ]);

      final encoded = workbook.encode();
      expect(encoded, isNotNull);

      final table = service.readFile(
        fileName: 'money_tracker.xlsx',
        bytes: Uint8List.fromList(encoded!),
      );

      expect(table.sheetName, 'Transactions');
      expect(table.looksLikeParagaMoneyTracker, isTrue);
      expect(service.detectMapping(table).incomeAmount, 3);
    });
  });

  group('Ledger/account export compatibility', () {
    test('repairs unquoted thousands comma and shifted columns', () {
      final bytes = Uint8List.fromList(
        utf8.encode(
          'Date,Ledger,Account,Category,Sub-Category,Amount,Currency,Note,Type\n'
          '1/10/2026,My Wallet,Cash,Housing,Housing,£4,233.33,EGP,dumbbell!,Expense\n'
          '1/10/2026,My Wallet,Cash,Charity,Charity,£1,0,EGP,,Expense\n'
          '1/10/2026,My Wallet,Cash,Family,Saqr,£12,0,EGP,,Expense\n',
        ),
      );

      final table = service.readFile(
        fileName: 'ledger_export.csv',
        bytes: bytes,
      );
      final mapping = service.detectMapping(table);
      final preview = service.preview(
        table: table,
        mapping: mapping,
        existingTransactions: const [],
      );

      expect(mapping.date, 0);
      expect(mapping.ledger, 1);
      expect(mapping.account, 2);
      expect(mapping.category, 3);
      expect(mapping.subCategory, 4);
      expect(mapping.amount, 5);
      expect(mapping.currency, 6);
      expect(mapping.note, 7);
      expect(mapping.type, 8);

      expect(preview.ready, hasLength(3));
      expect(preview.ready[0].type, TransactionType.expense);
      expect(preview.ready[0].amount, 4233.33);
      expect(preview.ready[0].store, 'dumbbell!');
      expect(preview.ready[0].category, 'Housing');
      expect(preview.ready[0].ledger, 'My Wallet');
      expect(preview.ready[0].account, 'Cash');
      expect(preview.ready[0].currencyCode, 'EGP');
      expect(preview.ready[0].note, 'Housing');

      expect(preview.ready[2].category, 'Family');
      expect(preview.ready[2].note, 'Saqr');
      expect(preview.ready[2].ledger, 'My Wallet');
      expect(preview.ready[2].account, 'Cash');
      expect(preview.ready[2].currencyCode, 'EGP');
    });
  });

  group('Money Tracker by Paraga import compatibility', () {
    test('imports signed Amount(Auto) layout', () {
      final table = ImportTable(
        fileName: 'money_tracker.csv',
        sheetName: null,
        headers: const ['Date', 'Category', 'Remark', 'Amount'],
        rows: const [
          ['25-09-2026', 'Salary', 'September salary', '15000'],
          ['26-09-2026', 'Food', 'Groceries', '-650.50'],
        ],
        looksLikeParagaMoneyTracker: true,
      );

      final mapping = service.detectMapping(table);
      final preview = service.preview(
        table: table,
        mapping: mapping,
        existingTransactions: const [],
      );

      expect(mapping.date, 0);
      expect(mapping.category, 1);
      expect(mapping.description, 2);
      expect(mapping.amount, 3);
      expect(preview.ready, hasLength(2));
      expect(preview.ready[0].type, TransactionType.income);
      expect(preview.ready[0].amount, 15000);
      expect(preview.ready[1].type, TransactionType.expense);
      expect(preview.ready[1].amount, 650.50);
      expect(preview.invalidCount, 0);
    });

    test('imports split Income and Expense layout and preserves wallet data', () {
      final table = ImportTable(
        fileName: 'money_tracker.xlsx',
        sheetName: 'Transactions',
        headers: const [
          'Date',
          'Category',
          'Remark',
          'Income',
          'Expense',
          'Wallet',
          'Currency',
        ],
        rows: const [
          [
            '2026/09/25',
            'Salary',
            'Salary',
            '15000',
            '',
            'Bank',
            'EGP',
          ],
          [
            '2026/09/26',
            'Transport',
            'Uber',
            '',
            '120',
            'Cash',
            'EGP',
          ],
        ],
        looksLikeParagaMoneyTracker: true,
      );

      final mapping = service.detectMapping(table);
      final preview = service.preview(
        table: table,
        mapping: mapping,
        existingTransactions: const [],
      );

      expect(mapping.incomeAmount, 3);
      expect(mapping.expenseAmount, 4);
      expect(mapping.wallet, 5);
      expect(mapping.currency, 6);
      expect(preview.ready, hasLength(2));
      expect(preview.ready[0].type, TransactionType.income);
      expect(preview.ready[1].type, TransactionType.expense);
      expect(preview.ready[0].ledger, 'Bank');
      expect(preview.ready[0].currencyCode, 'EGP');
    });

    test('skips Money Tracker transfer rows', () {
      final table = ImportTable(
        fileName: 'money_tracker.csv',
        sheetName: null,
        headers: const ['Date', 'Category', 'Remark', 'Amount', 'Type'],
        rows: const [
          ['01-10-2026', 'Transfer Out', 'Cash to bank', '-500', 'Transfer'],
          ['01-10-2026', 'Food', 'Lunch', '-100', 'Expense'],
        ],
        looksLikeParagaMoneyTracker: true,
      );

      final preview = service.preview(
        table: table,
        mapping: service.detectMapping(table),
        existingTransactions: const [],
      );

      expect(preview.transferCount, 1);
      expect(preview.ready, hasLength(1));
      expect(preview.ready.single.store, 'Lunch');
    });

    test('re-import detects duplicates while preserving legitimate repeats', () {
      final existing = [
        Transaction(
          id: 'existing-1',
          store: 'Coffee',
          amount: 50,
          category: 'Food',
          date: DateTime(2026, 10, 1),
          type: TransactionType.expense,
        ),
      ];

      final table = ImportTable(
        fileName: 'money_tracker.csv',
        sheetName: null,
        headers: const ['Date', 'Category', 'Remark', 'Amount'],
        rows: const [
          ['01-10-2026', 'Food', 'Coffee', '-50'],
          ['01-10-2026', 'Food', 'Coffee', '-50'],
        ],
        looksLikeParagaMoneyTracker: true,
      );

      final preview = service.preview(
        table: table,
        mapping: service.detectMapping(table),
        existingTransactions: existing,
      );

      expect(preview.duplicateCount, 1);
      expect(preview.ready, hasLength(1));
    });

    test('supports Paraga documented date formats', () {
      final table = ImportTable(
        fileName: 'money_tracker.csv',
        sheetName: null,
        headers: const ['Date', 'Category', 'Remark', 'Amount'],
        rows: const [
          ['05-Dec-1996', 'Food', 'A', '-1'],
          ['Dec/05/1996', 'Food', 'B', '-2'],
          ['1996/12/05', 'Food', 'C', '-3'],
        ],
        looksLikeParagaMoneyTracker: true,
      );

      final preview = service.preview(
        table: table,
        mapping: service.detectMapping(table),
        existingTransactions: const [],
      );

      expect(preview.ready, hasLength(3));
      for (final item in preview.ready) {
        expect(item.date.year, 1996);
        expect(item.date.month, 12);
        expect(item.date.day, 5);
      }
    });
  });
}
