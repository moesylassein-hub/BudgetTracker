import 'dart:convert';
import 'dart:io';

import 'package:budget_tracker/models/sheet_change.dart';
import 'package:budget_tracker/controllers/app_controller.dart';
import 'package:budget_tracker/models/transaction.dart';
import 'package:budget_tracker/services/local_storage_service.dart';
import 'package:budget_tracker/services/sheet_sync_service.dart';
import 'package:budget_tracker/services/drive_backup_service.dart';
import 'package:budget_tracker/services/notification_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const sheetId = 'shared_budget_sheet_1234567890';

Transaction item(String id, double amount) => Transaction(
  id: id,
  store: 'Travel',
  amount: amount,
  category: 'Transport',
  date: DateTime(2026, 10, 2),
  currencyCode: 'EGP',
);

Map<String, dynamic> snapshot(List<Transaction> items) => {
  'transactions': items.map((item) => item.toJson()).toList(),
  'categories': [],
  'goals': [],
  'recurringTransactions': [],
  'monthlyBudget': 10000,
  'currencyCode': 'EGP',
  'budgetCycleStartDay': 25,
};

SheetChange change(
  String id,
  Transaction? value, {
  String entity = 'transaction:travel',
  List<String> parents = const [],
}) => SheetChange(
  id: id,
  entity: entity,
  parents: parents,
  author: 'one@example.com',
  value: value?.toJson(),
);

class SheetServer {
  final List<List<dynamic>> rows = [List.of(SheetChange.columns)];
  bool offline = false;
  bool loseAppendResponse = false;
  Map<String, dynamic>? permission;
  int appends = 0;
  http.Client client() => MockClient((request) async {
    if (offline) throw const SocketException('offline');
    expect(request.headers['authorization'], 'Bearer test');
    if (request.url.path.endsWith('/permissions')) {
      permission = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      return http.Response('{}', 200);
    }
    if (request.url.path.endsWith(':append')) {
      expect(request.url.queryParameters['valueInputOption'], 'RAW');
      expect(request.url.queryParameters['insertDataOption'], 'INSERT_ROWS');
      rows.addAll(
        ((jsonDecode(request.body) as Map)['values'] as List).cast<List>(),
      );
      appends++;
      if (loseAppendResponse) {
        loseAppendResponse = false;
        throw const SocketException('response lost after commit');
      }
      return http.Response('{}', 200);
    }
    if (request.url.path.contains('/values/')) {
      return http.Response(jsonEncode({'values': rows}), 200);
    }
    return http.Response(
      jsonEncode({
        'properties': {'title': 'Family'},
      }),
      200,
    );
  });
  SheetSyncService phone(String email) =>
      SheetSyncService(
          ({bool interactive = false}) async => {
            'authorization': 'Bearer test',
          },
          client: client(),
        )
        ..sheetId = sheetId
        ..accountEmail = email;
}

class WorkspaceStorage extends LocalStorageService {
  final List<Transaction> items;
  WorkspaceStorage(this.items, {super.workspaceId});
  @override
  Future<List<Transaction>> loadTransactions() async => List.of(items);
  @override
  Future<void> updateTransaction(Transaction transaction) async {
    items[items.indexWhere((item) => item.id == transaction.id)] = transaction;
  }

  @override
  Future<void> insertTransaction(Transaction transaction) async =>
      items.add(transaction);
  @override
  Future<void> restoreFinancialSnapshot(Map<String, dynamic> data) async {
    items
      ..clear()
      ..addAll(
        (data['transactions'] as List).map(
          (raw) => Transaction.fromJson(Map<String, dynamic>.from(raw as Map)),
        ),
      );
    await saveBudget((data['monthlyBudget'] as num).toDouble());
    await saveCurrencyCode(data['currencyCode'] as String);
    await saveBudgetCycleStartDay(data['budgetCycleStartDay'] as int);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'different Google accounts sync additions, signed refunds, edits and deletions',
    () async {
      final server = SheetServer();
      final one = server.phone('one@example.com');
      final two = server.phone('two@example.com');
      addTearDown(one.dispose);
      addTearDown(two.dispose);
      await one.record(snapshot([item('travel', 1000), item('refund', -800)]));
      await one.sync();
      await two.sync();
      expect(two.ledger.entities['transaction:refund']!['amount'], -800);
      expect(two.ledger.snapshot({})['budgetCycleStartDay'], 25);
      await two.record(snapshot([item('travel', 900), item('refund', -800)]));
      await two.sync();
      await one.sync();
      expect(one.ledger.entities['transaction:travel']!['amount'], 900);
      await one.record(snapshot([item('refund', -800)]));
      await one.sync();
      await two.sync();
      expect(two.ledger.entities.containsKey('transaction:travel'), isFalse);
      expect(two.ledger.conflicts, isEmpty);
    },
  );

  test(
    'simultaneous offline edits preserve both branches and explicit resolution',
    () async {
      final server = SheetServer();
      final one = server.phone('one@example.com');
      final two = server.phone('two@example.com');
      addTearDown(one.dispose);
      addTearDown(two.dispose);
      await one.record(snapshot([item('travel', 1000)]));
      await one.sync();
      await two.sync();
      await one.record(snapshot([item('travel', 800)]));
      await two.record(snapshot([item('travel', -200)]));
      await Future.wait([one.sync(), two.sync()]);
      await one.sync();
      await two.sync();
      final versions = one.ledger.conflicts['transaction:travel']!;
      expect(versions.map((change) => change.value!['amount']).toSet(), {
        800.0,
        -200.0,
      });
      expect(two.ledger.conflicts.length, 1);
      await one.resolve(
        'transaction:travel',
        versions.firstWhere((v) => v.value!['amount'] == -200),
      );
      await one.sync();
      await two.sync();
      expect(two.ledger.conflicts, isEmpty);
      expect(two.ledger.entities['transaction:travel']!['amount'], -200);
    },
  );

  test(
    'ambiguous successful append is acknowledged without a second upload',
    () async {
      final server = SheetServer()..loseAppendResponse = true;
      final phone = server.phone('one@example.com');
      addTearDown(phone.dispose);
      await phone.record(snapshot([item('travel', 1000)]));
      await expectLater(phone.sync(), throwsA(isA<SocketException>()));
      expect(phone.pending, isNotEmpty);
      final restarted = server.phone('one@example.com');
      await phone.persist(activate: true);
      await restarted.restore();
      addTearDown(restarted.dispose);
      await restarted.sync();
      expect(restarted.pending, isEmpty);
      expect(server.appends, 1);
      expect(restarted.ledger.entities['transaction:travel']!['amount'], 1000);
    },
  );

  test(
    'offline queue survives restart and personal preferences are isolated',
    () async {
      final server = SheetServer()..offline = true;
      final phone = server.phone('one@example.com');
      addTearDown(phone.dispose);
      await phone.record(snapshot([item('refund', -800)]));
      await phone.persist(activate: true);
      await expectLater(phone.sync(), throwsA(isA<SocketException>()));
      await expectLater(phone.leave(), throwsStateError);
      final personal = LocalStorageService();
      final shared = LocalStorageService(workspaceId: sheetId);
      await personal.saveBudget(2000);
      await shared.saveBudget(7000);
      expect(await personal.loadBudget(), 2000);
      expect(await shared.loadBudget(), 7000);
      final restarted = server.phone('one@example.com');
      addTearDown(restarted.dispose);
      await restarted.restore();
      server.offline = false;
      await restarted.sync();
      expect(restarted.ledger.entities['transaction:refund']!['amount'], -800);
      expect(restarted.pending, isEmpty);
    },
  );

  test(
    'direct Sheet cell changes sync back, invalid rows never replace good data',
    () async {
      final server = SheetServer();
      final phone = server.phone('one@example.com');
      addTearDown(phone.dispose);
      await phone.record(snapshot([item('travel', 1000)]));
      await phone.sync();
      final row = server.rows.firstWhere(
        (row) => row.length > 1 && row[1] == 'transaction:travel',
      );
      row[8] = -800;
      await phone.sync();
      expect(phone.ledger.entities['transaction:travel']!['amount'], -800);
      expect(phone.ledger.conflicts, isEmpty);
      row[8] = 'invalid';
      await expectLater(phone.sync(), throwsFormatException);
      expect(phone.ledger.entities['transaction:travel']!['amount'], -800);
    },
  );

  test(
    'removed history pauses sync instead of resurrecting or erasing entries',
    () async {
      final server = SheetServer();
      final phone = server.phone('one@example.com');
      addTearDown(phone.dispose);
      await phone.record(snapshot([item('travel', 1000)]));
      await phone.sync();
      server.rows.removeAt(1);
      await expectLater(phone.sync(), throwsFormatException);
      expect(phone.ledger.entities['transaction:travel']!['amount'], 1000);
    },
  );

  test(
    'delete versus edit conflicts, identical recurring occurrences deduplicate',
    () {
      final ledger = SheetLedger();
      final base = change('base', item('travel', 100));
      final duplicate = change('duplicate', item('travel', 100));
      ledger.addAll([base, duplicate]);
      expect(ledger.conflicts, isEmpty);
      final deletion = ledger
          .edits(snapshot([]), 'one@example.com')
          .firstWhere((change) => change.entity == 'transaction:travel');
      expect(deletion.parents.toSet(), {base.revision, duplicate.revision});
      ledger.addAll([
        deletion,
        change('edit', item('travel', 200), parents: [base.revision]),
      ]);
      expect(ledger.conflicts['transaction:travel']!.length, 2);
    },
  );

  test(
    'invite grants editor permission without making the Sheet public',
    () async {
      final server = SheetServer();
      final phone = server.phone('owner@example.com');
      addTearDown(phone.dispose);
      await phone.invite('guest@example.com');
      expect(server.permission, {
        'type': 'user',
        'role': 'writer',
        'emailAddress': 'guest@example.com',
      });
      await expectLater(phone.invite('invalid'), throwsFormatException);
    },
  );

  test('Sheet links are validated and transaction text stays plain text', () {
    expect(
      SheetSyncService.parseId(
        'https://docs.google.com/spreadsheets/d/$sheetId/edit',
      ),
      sheetId,
    );
    expect(
      () => SheetSyncService.parseId('https://malicious.example/$sheetId'),
      throwsFormatException,
    );
    final tx = item('travel', -800).copyWith(store: '=IMPORTXML("bad")');
    final original = change('operation', tx);
    final restored = SheetChange.fromRow(original.toRow());
    expect(restored.revision, original.revision);
    expect(restored.value!['store'], tx.store);
  });

  test(
    'download application marker survives restart until completion',
    () async {
      final server = SheetServer();
      final phone = server.phone('one@example.com');
      addTearDown(phone.dispose);
      await phone.record(snapshot([item('travel', 1000)]));
      await phone.persist(activate: true);
      await phone.sync();
      await phone.finishApplication();
      final other = server.phone('two@example.com');
      addTearDown(other.dispose);
      await other.sync();
      await other.record(snapshot([item('travel', -800)]));
      await other.sync();
      await phone.sync(localSnapshot: snapshot([item('travel', 1000)]));
      final restarted = server.phone('one@example.com');
      addTearDown(restarted.dispose);
      await restarted.restore();
      expect(restarted.pendingApplication!['transactions'][0]['amount'], -800);
      await restarted.finishApplication();
      final again = server.phone('one@example.com');
      addTearDown(again.dispose);
      await again.restore();
      expect(again.pendingApplication, isNull);
    },
  );

  test(
    'app applies shared data, preserves stale editor changes and returns to personal data',
    () async {
      final server = SheetServer();
      final seed = server.phone('one@example.com');
      addTearDown(seed.dispose);
      await seed.record(snapshot([item('travel', 1000)]));
      await seed.sync();
      await seed.persist(activate: true);
      final personal = WorkspaceStorage([item('personal', 500)]);
      final shared = WorkspaceStorage([
        item('travel', 1000),
      ], workspaceId: sheetId);
      await shared.saveBudgetCycleStartDay(25);
      final app = await AppController.create(
        personal,
        NotificationService(),
        DriveBackupService(),
        workspaceStorage: (_) => shared,
        sharedServiceFactory: () => server.phone('one@example.com'),
      );
      addTearDown(app.dispose);
      app.setAppActive(false);
      expect(app.sharedBudgetActive, isTrue);
      expect(app.transactions.single.id, 'travel');
      final editorRevision = app.sharedRevision('transaction:travel')!;
      final other = server.phone('two@example.com');
      addTearDown(other.dispose);
      await other.sync();
      await other.recordVersion(
        'transaction:travel',
        item('travel', 900).toJson(),
        editorRevision,
      );
      await other.sync();
      await app.syncSharedBudget();
      expect(app.sharedSyncError, isNull);
      expect(app.transactions.single.amount, 900);
      // The editor was opened at 1000; it must not silently overwrite 900.
      await app.updateTransaction(
        item('travel', -800),
        revision: editorRevision,
      );
      expect(app.sharedConflicts['transaction:travel']!.length, 2);
      final refund = app.sharedConflicts['transaction:travel']!.firstWhere(
        (v) => v.value!['amount'] == -800,
      );
      await app.resolveSharedConflict('transaction:travel', refund);
      await app.syncSharedBudget();
      expect(app.currentMonthSpent, -800);
      expect(app.currentMonthIncome, 0);
      expect(app.sharedPendingCount, 0);
      await app.leaveSharedBudget();
      expect(app.sharedBudgetActive, isFalse);
      expect(app.transactions.single.id, 'personal');
      expect(personal.items.single.amount, 500);
    },
  );
}
