import 'dart:convert';

import 'package:budget_tracker/controllers/app_controller.dart';
import 'package:budget_tracker/models/recurring_transaction.dart';
import 'package:budget_tracker/models/transaction.dart';
import 'package:budget_tracker/services/drive_backup_service.dart';
import 'package:budget_tracker/services/export_service.dart';
import 'package:budget_tracker/services/import_service.dart';
import 'package:budget_tracker/services/local_storage_service.dart';
import 'package:budget_tracker/services/notification_service.dart';
import 'package:budget_tracker/widgets/transaction_card.dart';
import 'package:budget_tracker/utils/formatters.dart';
import 'package:budget_tracker/screens/add_transaction.dart';
import 'package:budget_tracker/screens/reports.dart';
import 'package:budget_tracker/screens/statistics.dart';
import 'package:excel/excel.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryStorage extends LocalStorageService {
  final List<Transaction> items;
  MemoryStorage(this.items);

  @override
  Future<List<Transaction>> loadTransactions() async => List.of(items);
  @override
  Future<void> insertTransaction(Transaction transaction) async =>
      items.add(transaction);
  @override
  Future<void> updateTransaction(Transaction transaction) async {
    items[items.indexWhere((item) => item.id == transaction.id)] = transaction;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Transaction item(
    String id,
    double amount, {
    TransactionType type = TransactionType.expense,
  }) => Transaction(
    id: id,
    store: 'Travel',
    amount: amount,
    category: 'Travel',
    date: DateTime.now(),
    type: type,
  );

  Future<AppController> controller(MemoryStorage storage) =>
      AppController.create(
        storage,
        NotificationService(),
        DriveBackupService(),
      );

  test(
    'net expenses, income, budgets and edits preserve reimbursements',
    () async {
      final storage = MemoryStorage([
        item('purchase', 1000),
        item('refund', -800),
        item('income', 2000, type: TransactionType.income),
      ]);
      final app = await controller(storage);
      addTearDown(app.dispose);
      expect(app.currentMonthSpent, 200);
      expect(app.currentMonthIncome, 2000);
      expect(app.currentMonthNet, 1800);
      expect(app.remaining, 9800);
      expect(app.categorySpent('Travel', DateTime.now()), 200);
      await app.updateTransaction(storage.items[1].copyWith(amount: -1200));
      expect(app.currentMonthSpent, -200);
      expect(app.remaining, 10200);
      expect(app.currentMonthNet, 2200);
      final reloaded = await controller(storage);
      addTearDown(reloaded.dispose);
      expect(reloaded.currentMonthSpent, -200);
    },
  );

  test(
    'negative recurring expenses survive reload and generate once',
    () async {
      final storage = MemoryStorage([]);
      final today = DateTime.now();
      final rule = RecurringTransaction(
        id: 'reimbursement',
        title: 'Travel reimbursement',
        amount: -800,
        category: 'Other',
        type: TransactionType.expense,
        frequency: RecurringFrequency.monthly,
        startDate: DateTime(today.year, today.month, today.day),
        dayOfMonth: today.day,
        weekday: today.weekday,
        createdAt: today,
      );
      await storage.saveRecurringTransactions([rule]);
      expect((await storage.loadRecurringTransactions()).single.amount, -800);
      final app = await controller(storage);
      addTearDown(app.dispose);
      expect(await app.processRecurringTransactions(), 1);
      expect(app.transactions.single.amount, -800);
      expect(app.transactions.single.isExpense, isTrue);
      expect(app.currentMonthIncome, 0);
      expect(await app.processRecurringTransactions(), 0);
      final reloaded = await controller(storage);
      addTearDown(reloaded.dispose);
      expect(await reloaded.processRecurringTransactions(), 0);
      expect(reloaded.recurringTransactions.single.amount, -800);
    },
  );

  for (final extension in ['csv', 'xlsx']) {
    test('$extension export/import preserves expense signs and duplicates', () {
      final items = [
        item('purchase', 1000),
        item('refund', -800),
        item('income', 2000, type: TransactionType.income),
      ];
      const exporter = ExportService();
      final bytes = extension == 'csv'
          ? exporter.encodeCsv(
              transactions: items,
              currencyCode: 'EGP',
              budgetCycleStartDay: 1,
            )
          : exporter.encodeExcel(
              transactions: items,
              currencyCode: 'EGP',
              budgetCycleStartDay: 1,
            );
      if (extension == 'csv') {
        expect(utf8.decode(bytes), contains('-800.00'));
      } else {
        final summary = Excel.decodeBytes(bytes)['Summary'].rows;
        expect(summary[4][1]!.value, DoubleCellValue(2000));
        expect(summary[5][1]!.value, DoubleCellValue(200));
        expect(summary[6][1]!.value, DoubleCellValue(1800));
      }
      const importer = ImportService();
      final table = importer.readFile(
        fileName: 'export.$extension',
        bytes: bytes,
      );
      final preview = importer.preview(
        table: table,
        mapping: importer.detectMapping(table),
        existingTransactions: const [],
      );
      expect(preview.ready.map((item) => item.amount), [1000, -800, 2000]);
      expect(preview.ready[1].isExpense, isTrue);
      final repeat = importer.preview(
        table: table,
        mapping: importer.detectMapping(table),
        existingTransactions: preview.ready,
      );
      expect(repeat.duplicateCount, 3);
      expect(repeat.ready, isEmpty);
    });
  }

  testWidgets('refund card shows positive cash flow without double minus', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TransactionCard(
            transaction: item('refund', -800),
            currencyCode: 'EGP',
          ),
        ),
      ),
    );
    expect(find.text('+${AppFormatters.money(800)}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing an expense accepts and persists a negative amount', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final storage = MemoryStorage([item('purchase', 800)]);
    final app = await controller(storage);
    addTearDown(app.dispose);
    Transaction? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.push<Transaction>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddTransactionScreen(
                      controller: app,
                      transaction: storage.items.single,
                    ),
                  ),
                );
              },
              child: const Text('Edit'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    final amount = find.byWidgetPredicate(
      (widget) =>
          widget is TextFormField && widget.decoration?.labelText == 'Amount',
    );
    await tester.enterText(amount, '-800');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(result?.amount, -800);
    await app.updateTransaction(result!);
    expect(storage.items.single.amount, -800);
    expect(app.currentMonthIncome, 0);
    expect(tester.takeException(), isNull);
  });

  for (final refund in [-100.0, -200.0, -300.0]) {
    testWidgets('charts and reports handle net spending ${100 + refund}', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final app = await controller(
        MemoryStorage([
          item('purchase', 100).copyWith(category: 'Food'),
          item('refund', refund),
        ]),
      );
      addTearDown(app.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: StatisticsScreen(controller: app)),
        ),
      );
      await tester.pumpAndSettle();
      final pie = tester.widget<PieChart>(find.byType(PieChart));
      expect(pie.data.sections.every((section) => section.value > 0), isTrue);
      expect(find.text(AppFormatters.money(refund)), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReportsScreen(controller: app)),
        ),
      );
      await tester.pumpAndSettle();
      final line = tester.widget<LineChart>(find.byType(LineChart));
      expect(line.data.minY, lessThanOrEqualTo(100 + refund));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Trends'));
      await tester.pumpAndSettle();
      final bars = tester.widget<BarChart>(find.byType(BarChart));
      expect(bars.data.minY, lessThanOrEqualTo(100 + refund));
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();
      final donut = tester.widget<PieChart>(find.byType(PieChart));
      expect(donut.data.sections.every((section) => section.value > 0), isTrue);
      expect(find.text(AppFormatters.money(refund)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('refund-only reports omit pies and largest purchase', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1200, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final app = await controller(MemoryStorage([item('refund', -800)]));
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: StatisticsScreen(controller: app)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PieChart), findsNothing);
    expect(find.textContaining('Largest expense:'), findsNothing);
    expect(find.text(AppFormatters.money(-800)), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ReportsScreen(controller: app)),
      ),
    );
    await tester.tap(find.text('Categories'));
    await tester.pumpAndSettle();
    expect(find.byType(PieChart), findsNothing);
    expect(find.text(AppFormatters.money(-800)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
