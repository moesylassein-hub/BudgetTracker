import 'dart:convert';
import 'dart:io';

import 'package:budget_tracker/models/sheet_change.dart';
import 'package:budget_tracker/models/budget_access.dart';
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
  final List<List<dynamic>> transactionRows = [];
  final Set<String> sheetTitles = {'Changes', 'Read me'};
  final List<String> changeReadRanges = [];
  bool offline = false;
  bool denied = false;
  bool loseAppendResponse = false;
  Map<String, dynamic>? permission;
  int appends = 0;
  int sheetCreates = 0;
  int mirrorWrites = 0;
  int gridRows = 1000;
  int historyGridRows = 1000;
  bool failMirror = false;
  bool hidePermissions = false;
  final List<String?> permissionPages = [];
  final List<Map<String, dynamic>> sharing = [
    {
      'type': 'user',
      'role': 'owner',
      'displayName': 'Owner',
      'emailAddress': 'one@example.com',
    },
    {
      'type': 'user',
      'role': 'writer',
      'displayName': 'Editor',
      'emailAddress': 'two@example.com',
    },
  ];

  http.Client client() => MockClient((request) async {
    if (offline) throw const SocketException('offline');
    if (denied) return http.Response('{}', 403);
    expect(request.headers['authorization'], 'Bearer test');

    if (request.method == 'POST' && request.url.path == '/v4/spreadsheets') {
      sheetCreates++;
      final body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      final sheets = body['sheets'] as List? ?? const [];
      for (final raw in sheets.whereType<Map>()) {
        final properties = raw['properties'];
        if (properties is Map && properties['title'] != null) {
          sheetTitles.add(properties['title'].toString());
        }
      }
      return http.Response(jsonEncode({'spreadsheetId': sheetId}), 200);
    }

    if (request.method == 'GET' && request.url.path.endsWith('/permissions')) {
      if (hidePermissions) return http.Response('{}', 403);
      final token = request.url.queryParameters['pageToken'];
      permissionPages.add(token);
      return http.Response(
        jsonEncode({
          'permissions': token == null
              ? sharing.take(1).toList()
              : sharing.skip(1).toList(),
          if (token == null && sharing.length > 1) 'nextPageToken': 'next',
        }),
        200,
      );
    }
    if (request.method == 'GET' && request.url.host == 'www.googleapis.com') {
      return http.Response(
        jsonEncode({
          'name': 'Family',
          'owners': [
            {'displayName': 'Owner', 'emailAddress': 'one@example.com'},
          ],
          'capabilities': {'canEdit': true, 'canShare': true},
        }),
        200,
      );
    }
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
      if (rows.length > historyGridRows) historyGridRows = rows.length;
      appends++;
      if (loseAppendResponse) {
        loseAppendResponse = false;
        throw const SocketException('response lost after commit');
      }
      return http.Response('{}', 200);
    }

    if (request.url.path.endsWith('/values:batchClear')) {
      final body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      final ranges = (body['ranges'] as List? ?? const []).cast<String>();
      if (ranges.any((range) => range.startsWith('Transactions!'))) {
        transactionRows.clear();
      }
      return http.Response('{}', 200);
    }

    if (request.url.path.endsWith('/values:batchUpdate')) {
      final body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      for (final raw in (body['data'] as List? ?? const []).whereType<Map>()) {
        final range = raw['range']?.toString() ?? '';
        final values = (raw['values'] as List? ?? const [])
            .map((row) => List<dynamic>.from(row as List))
            .toList();
        if (range.startsWith('Transactions!')) {
          transactionRows
            ..clear()
            ..addAll(values);
        } else if (range.startsWith('Changes!') && values.isNotEmpty) {
          rows
            ..clear()
            ..addAll(values);
        }
      }
      return http.Response('{}', 200);
    }

    if (request.method == 'POST' && request.url.path.endsWith(':batchUpdate')) {
      final body = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      final operations = (body['requests'] as List? ?? const [])
          .whereType<Map>()
          .toList();
      if (failMirror && operations.any((raw) => raw['updateCells'] != null)) {
        return http.Response('{}', 500);
      }
      for (final raw in operations) {
        final append = raw['appendDimension'];
        if (append is Map && append['dimension'] == 'ROWS') {
          gridRows += append['length'] as int;
        }
        final update = raw['updateCells'];
        if (update is Map) {
          expect(update['fields'], 'userEnteredValue');
          expect((update['range'] as Map)['endColumnIndex'], 10);
          final updated = (update['rows'] as List)
              .map(
                (raw) => ((raw as Map)['values'] as List).map((cell) {
                  final value = (cell as Map)['userEnteredValue'] as Map;
                  expect(value.containsKey('formulaValue'), isFalse);
                  return value['numberValue'] ?? value['stringValue'];
                }).toList(),
              )
              .toList();
          expect(updated.length, lessThanOrEqualTo(gridRows));
          transactionRows
            ..clear()
            ..addAll(updated);
          mirrorWrites++;
        }
        final addSheet = raw['addSheet'];
        if (addSheet is Map) {
          final properties = addSheet['properties'];
          if (properties is Map && properties['title'] != null) {
            sheetTitles.add(properties['title'].toString());
          }
        }
      }
      return http.Response('{}', 200);
    }

    if (request.url.path.contains('/values/Changes!')) {
      final range = request.url.path.split('/values/').last;
      changeReadRanges.add(range);
      if (range == 'Changes!A:O') {
        return http.Response(jsonEncode({'values': rows}), 200);
      }
      final match = RegExp(r'^Changes!A(\d+):O$').firstMatch(range);
      if (match == null) {
        return http.Response(jsonEncode({'values': rows}), 200);
      }
      final startRow = int.parse(match.group(1)!);
      if (startRow > historyGridRows) {
        return http.Response('Range exceeds grid limits', 400);
      }
      final startIndex = (startRow - 1).clamp(0, rows.length);
      return http.Response(
        jsonEncode({'values': rows.skip(startIndex).toList()}),
        200,
      );
    }
    if (request.url.path.contains('/values/Transactions!')) {
      return http.Response(jsonEncode({'values': transactionRows}), 200);
    }

    return http.Response(
      jsonEncode({
        'properties': {'title': 'Family'},
        'sheets': [
          for (final title in sheetTitles)
            {
              'properties': {
                'title': title,
                'sheetId': sheetTitles.toList().indexOf(title),
                'gridProperties': {'rowCount': gridRows, 'columnCount': 26},
              },
            },
        ],
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

class TestDriveBackup extends DriveBackupService {
  @override
  String get accountEmail => 'one@example.com';
  @override
  Future<Map<String, String>> sharedSheetHeaders({
    bool interactive = false,
  }) async => {'authorization': 'Bearer test'};
}

class WorkspaceStorage extends LocalStorageService {
  final List<Transaction> items;
  int restoreCount = 0;
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
    restoreCount++;
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

  test('budget access uses Google ownership, paginates editors and persists details', () async {
    final server = SheetServer();
    final phone = server.phone('two@example.com');
    addTearDown(phone.dispose);
    await phone.refreshAccess();
    expect(phone.access!.roleFor('ONE@example.com'), 'Owner');
    expect(phone.access!.roleFor('two@example.com'), 'Invited editor');
    expect(phone.access!.members.map((member) => member.email), [
      'one@example.com',
      'two@example.com',
    ]);
    expect(server.permissionPages, [null, 'next']);
    expect(phone.accessError, isNull);
    expect(phone.access!.complete, isTrue);
    final restored = server.phone('two@example.com');
    addTearDown(restored.dispose);
    await restored.restore(sheet: sheetId);
    expect(restored.access!.roleFor('two@example.com'), 'Invited editor');
  });

  test('restricted sharing details and revoked access are explicit without blocking local data', () async {
    final server = SheetServer()..hidePermissions = true;
    final phone = server.phone('two@example.com');
    addTearDown(phone.dispose);
    await phone.refreshAccess();
    expect(phone.access!.complete, isFalse);
    expect(phone.access!.members.single.role, 'owner');
    expect(phone.access!.roleFor(phone.accountEmail), 'Editor');
    expect(phone.accessError, contains('full access list'));
    server.denied = true;
    await phone.refreshAccess();
    expect(phone.accessError, contains('last check'));
    await phone.leave();
  });

  test('group, domain and public access are labelled without inventing named members', () {
    expect(
      BudgetMember({
        'type': 'group',
        'emailAddress': 'team@example.com',
        'role': 'writer',
      }).label,
      'team@example.com',
    );
    expect(
      BudgetMember({
        'type': 'domain',
        'domain': 'example.com',
        'role': 'reader',
      }).label,
      'People at example.com',
    );
    expect(
      BudgetMember({'type': 'anyone', 'role': 'reader'}).label,
      'Anyone with the link',
    );
    final access = BudgetAccess(
      members: [],
      checkedAt: DateTime.now(),
      complete: true,
      canEdit: false,
    );
    expect(access.roleFor('someone@example.com'), 'Viewer');
    expect(access.roleFor(null), 'Unknown');
  });

  test('invalid cross-item history cannot advance the incremental cursor or alter cached state', () async {
    final server = SheetServer();
    final phone = server.phone('one@example.com');
    addTearDown(phone.dispose);
    await phone.record(snapshot([item('travel', 1000)]));
    await phone.sync();
    final original = phone.ledger.heads['transaction:travel']!.last;
    server.rows.add(
      SheetChange(
        id: 'bad',
        entity: 'transaction:bad',
        parents: [original.revision],
        author: 'two@example.com',
        value: item('bad', 50).toJson(),
      ).toRow(),
    );
    await expectLater(phone.sync(), throwsFormatException);
    expect(phone.ledger.entities['transaction:travel']!['amount'], 1000);
    expect(phone.ledger.entities.containsKey('transaction:bad'), isFalse);
    server.rows.removeLast();
    server.rows.add(
      SheetChange(
        id: 'fixed',
        entity: original.entity,
        parents: [original.revision],
        author: 'two@example.com',
        value: item('travel', 900).toJson(),
      ).toRow(),
    );
    await phone.sync();
    expect(phone.ledger.entities['transaction:travel']!['amount'], 900);
  });

  test('atomic mirror failure retains the previous view and retries with literal strings', () async {
    final server = SheetServer()..gridRows = 2;
    final phone = server.phone('one@example.com');
    addTearDown(phone.dispose);
    await phone.record(snapshot([item('travel', 1000)]));
    await phone.sync();
    final previous = jsonEncode(server.transactionRows);
    final formulaName = item('new', -800).copyWith(store: '=SUM(1,2)');
    await phone.record(snapshot([item('travel', 1000), formulaName]));
    server.failMirror = true;
    await expectLater(phone.sync(), throwsStateError);
    expect(jsonEncode(server.transactionRows), previous);
    server.failMirror = false;
    await phone.sync();
    expect(server.transactionRows, hasLength(3));
    expect(
      server.transactionRows.skip(1).any((row) => row[3] == '=SUM(1,2)'),
      isTrue,
    );
    expect(server.gridRows, 3);
    // Repair an externally overwritten mirror even when our ledger did not change.
    server.transactionRows.clear();
    await phone.sync(interactive: true);
    expect(server.transactionRows, hasLength(3));
  });

  test(
    'discard drops only pending additions edits and deletions before rejoining',
    () async {
      final server = SheetServer();
      final phone = server.phone('one@example.com');
      addTearDown(phone.dispose);
      await phone.record(
        snapshot([item('travel', 1000), item('existing', 500)]),
      );
      await phone.sync();
      final before = jsonEncode(server.rows);
      final appends = server.appends;
      await phone.record(snapshot([item('travel', -800), item('new', 200)]));
      expect(phone.pending, hasLength(3));
      await phone.discardPending();
      await phone.leave();
      expect(phone.pending, isEmpty);
      final rejoined = server.phone('one@example.com');
      addTearDown(rejoined.dispose);
      await rejoined.join(sheetId, 'one@example.com');
      expect(rejoined.ledger.entities['transaction:travel']!['amount'], 1000);
      expect(rejoined.ledger.entities['transaction:existing']!['amount'], 500);
      expect(rejoined.ledger.entities.containsKey('transaction:new'), isFalse);
      expect(server.appends, appends);
      expect(jsonEncode(server.rows), before);
    },
  );

  test('discard and switch works with revoked access and restores the cached workspace', () async {
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
    await app.updateTransaction(item('travel', -800));
    server.denied = true;
    await app.leaveSharedBudget(discardPending: true);
    expect(app.sharedBudgetActive, isFalse);
    expect(app.transactions.single.id, 'personal');
    expect(shared.items.single.amount, 1000);
    final cached = server.phone('one@example.com');
    addTearDown(cached.dispose);
    await cached.restore(sheet: sheetId);
    expect(cached.pending, isEmpty);
    expect(cached.pendingApplication, isNull);
    expect(cached.ledger.entities['transaction:travel']!['amount'], 1000);
  });

  test(
    'revoked access cannot trap the app or discard pending edits on rejoin',
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
      await app.updateTransaction(item('travel', -800));
      expect(app.sharedPendingCount, greaterThan(0));
      server.denied = true;
      await app.syncSharedBudget();
      expect(app.sharedSyncError, contains('Google denied access'));
      await app.leaveSharedBudget();
      expect(app.sharedBudgetActive, isFalse);
      expect(app.transactions.single.id, 'personal');
      expect(app.currentMonthSpent, 500);
      expect(shared.items.single.amount, -800);
      final restarted = await AppController.create(
        personal,
        NotificationService(),
        DriveBackupService(),
        workspaceStorage: (_) => shared,
        sharedServiceFactory: () =>
            server.phone('one@example.com')..sheetId = null,
      );
      addTearDown(restarted.dispose);
      expect(restarted.sharedBudgetActive, isFalse);
      expect(restarted.transactions.single.id, 'personal');
      final rejoined = server.phone('one@example.com');
      addTearDown(rejoined.dispose);
      await expectLater(
        rejoined.join(sheetId, 'one@example.com'),
        throwsStateError,
      );
      expect(rejoined.pending, isNotEmpty);
      server.denied = false;
      final retry = server.phone('one@example.com');
      addTearDown(retry.dispose);
      await retry.join(sheetId, 'one@example.com');
      expect(retry.ledger.entities['transaction:travel']!['amount'], -800);
      expect(retry.pending, isEmpty);
      expect(
        server.rows.where(
          (row) => row.length > 1 && row[1] == 'transaction:travel',
        ),
        hasLength(2),
      );
    },
  );

  test(
    'author names sync, retain the creator and survive restart per account',
    () async {
      final server = SheetServer();
      final one = server.phone('one@example.com');
      final two = server.phone('two@example.com');
      addTearDown(one.dispose);
      addTearDown(two.dispose);
      await one.setDisplayName('Mohamed');
      await one.record(snapshot([item('travel', 1000)]));
      await one.sync();
      await two.sync();
      expect(two.ledger.authorship('transaction:travel'), 'Added by Mohamed');
      await two.setDisplayName('Ahmed');
      await two.record(snapshot([item('travel', -800)]));
      await two.sync();
      await one.sync();
      expect(
        one.ledger.authorship('transaction:travel'),
        'Added by Mohamed\nLast edited by Ahmed',
      );
      expect(
        one.ledger.heads['transaction:travel']!.last.author,
        'Ahmed <two@example.com>',
      );
      await one.persist(activate: true);
      final restarted = server.phone('one@example.com');
      addTearDown(restarted.dispose);
      await restarted.restore();
      expect(restarted.displayName, 'Mohamed');
      await restarted.setAccount('two@example.com');
      expect(restarted.displayName, 'Ahmed');
      await restarted.setAccount('new@example.com');
      expect(restarted.displayName, isEmpty);
      expect(restarted.editor, 'new@example.com');
      await expectLater(
        restarted.setDisplayName('Bad <name>'),
        throwsFormatException,
      );
    },
  );

  test('conflict resolution retains creator attribution and missing history is unknown', () {
    final original = change('original', item('travel', 1000));
    final edit = SheetChange(
      id: 'edit',
      entity: original.entity,
      parents: [original.revision],
      author: 'Ahmed <two@example.com>',
      value: item('travel', 900).toJson(),
    );
    final other = SheetChange(
      id: 'other',
      entity: original.entity,
      parents: [original.revision],
      author: 'Mohamed <one@example.com>',
      value: item('travel', -800).toJson(),
    );
    final resolved = SheetChange(
      id: 'resolved',
      entity: original.entity,
      parents: [edit.revision, other.revision],
      author: 'Resolver <three@example.com>',
      value: other.value,
    );
    final ledger = SheetLedger()..addAll([original, edit, other, resolved]);
    expect(
      ledger.authorship(original.entity),
      'Added by one@example.com\nLast edited by Resolver',
    );
    expect(ledger.authorship('transaction:missing'), isNull);
    final incomplete = SheetLedger()..addAll([edit]);
    expect(
      incomplete.authorship(original.entity),
      'Added by Unknown\nLast edited by Ahmed',
    );
  });

  test('different Google accounts sync additions, signed refunds, edits and deletions', () async {
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
  });

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
      await phone.leave();
      final detached = SheetSyncService(
        ({bool interactive = false}) async => {},
        client: server.client(),
      );
      addTearDown(detached.dispose);
      await detached.restore();
      expect(detached.active, isFalse);
      final personal = LocalStorageService();
      final shared = LocalStorageService(workspaceId: sheetId);
      await personal.saveBudget(2000);
      await shared.saveBudget(7000);
      expect(await personal.loadBudget(), 2000);
      expect(await shared.loadBudget(), 7000);
      final restarted = server.phone('one@example.com');
      addTearDown(restarted.dispose);
      await restarted.restore(sheet: sheetId);
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
      await phone.sync(interactive: true);
      expect(phone.ledger.entities['transaction:travel']!['amount'], -800);
      expect(phone.ledger.conflicts, isEmpty);
      row[8] = 'invalid';
      await expectLater(phone.sync(interactive: true), throwsFormatException);
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
      await expectLater(phone.sync(interactive: true), throwsFormatException);
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

  test('saved links retain unique budgets in last-used order and forget only the link', () async {
    final server = SheetServer();
    final first = server.phone('one@example.com')..title = 'Family';
    final second = server.phone('two@example.com')
      ..sheetId = 'another_budget_sheet_1234567890'
      ..title = 'Travel';
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await first.record(snapshot([item('pending', -75)]));
    await first.persist(activate: true);
    await second.persist(activate: true);
    await first.leave();
    var saved = await SheetSyncService.savedBudgets();
    expect(saved.map((budget) => budget.name), ['Family', 'Travel']);
    expect(saved.first.accountEmail, 'one@example.com');
    await SheetSyncService.forgetBudget(sheetId);
    saved = await SheetSyncService.savedBudgets();
    expect(saved.single.sheetId, second.sheetId);
    final restored = server.phone('one@example.com');
    addTearDown(restored.dispose);
    await restored.restore(sheet: sheetId);
    expect(restored.pending, isNotEmpty);
    expect(restored.ledger.entities['transaction:pending']!['amount'], -75);
  });

  test('old active selections are remembered without network access', () async {
    final server = SheetServer();
    final phone = server.phone('one@example.com')..title = 'Old family';
    addTearDown(phone.dispose);
    await phone.record(snapshot([item('travel', 100)]));
    await phone.persist(activate: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('shared_sheet_saved_v1');
    server.offline = true;
    final app = await AppController.create(
      WorkspaceStorage([item('personal', 500)]),
      NotificationService(),
      TestDriveBackup(),
      workspaceStorage: (_) =>
          WorkspaceStorage([item('travel', 100)], workspaceId: sheetId),
      sharedServiceFactory: () => server.phone('one@example.com'),
    );
    addTearDown(app.dispose);
    app.setAppActive(false);
    expect(app.savedSharedBudgets.single.name, 'Old family');
    await app.leaveSharedBudget();
    expect(app.savedSharedBudgets.single.sheetId, sheetId);
    expect(app.transactions.single.id, 'personal');
  });

  test('saved budget reopening checks access and retries the cached outbox without creating Sheets', () async {
    final server = SheetServer();
    final seed = server.phone('one@example.com')..title = 'Family';
    addTearDown(seed.dispose);
    await seed.record(snapshot([item('travel', 100)]));
    await seed.sync();
    await seed.record(snapshot([item('travel', -75)]));
    await seed.persist(activate: true);
    await seed.leave();
    final personal = WorkspaceStorage([item('personal', 500)]);
    final shared = WorkspaceStorage([
      item('travel', -75),
    ], workspaceId: sheetId);
    final app = await AppController.create(
      personal,
      NotificationService(),
      TestDriveBackup(),
      workspaceStorage: (_) => shared,
      sharedServiceFactory: () => server.phone('one@example.com'),
    );
    addTearDown(app.dispose);
    app.setAppActive(false);
    final savedId = app.savedSharedBudgets.single.sheetId;
    server.denied = true;
    await expectLater(app.openSharedBudget(link: savedId), throwsStateError);
    expect(app.sharedBudgetActive, isFalse);
    expect(app.transactions.single.id, 'personal');
    expect(app.savedSharedBudgets.single.sheetId, savedId);
    server.denied = false;
    await app.openSharedBudget(link: savedId);
    expect(app.sharedBudgetId, savedId);
    expect(app.sharedPendingCount, 0);
    expect(app.transactions.single.amount, -75);
    expect(personal.items.single.amount, 500);
    expect(server.sheetCreates, 0);
    expect(app.savedSharedBudgets, hasLength(1));
  });

  test('long-running sync reads a checkpoint and new history rows', () async {
    final server = SheetServer();
    for (var i = 0; i < 400; i++) {
      server.rows.add(
        change(
          'seed-$i',
          item('seed-$i', i + 1),
          entity: 'transaction:seed-$i',
        ).toRow(),
      );
    }

    final phone = server.phone('one@example.com');
    addTearDown(phone.dispose);
    await phone.sync(interactive: true);
    expect(server.changeReadRanges.last, 'Changes!A:O');

    server.changeReadRanges.clear();
    await phone.sync();
    expect(server.changeReadRanges, ['Changes!A401:O']);

    server.rows.add(
      change('late', item('late', -75), entity: 'transaction:late').toRow(),
    );
    await phone.sync();
    expect(server.changeReadRanges.last, 'Changes!A401:O');
    expect(phone.ledger.entities['transaction:late']!['amount'], -75);

    await phone.sync();
    expect(server.changeReadRanges.last, 'Changes!A402:O');
  });

  test('polling at the grid boundary keeps working without new rows', () async {
    final server = SheetServer();
    server.rows.add(change('seed', item('travel', 100)).toRow());
    server.historyGridRows = server.rows.length;
    final phone = server.phone('one@example.com');
    addTearDown(phone.dispose);
    await phone.sync();
    await phone.finishApplication();
    await phone.sync();
    expect(server.changeReadRanges.last, 'Changes!A2:O');
    expect(phone.pendingApplication, isNull);
    expect(phone.ledger.entities['transaction:travel']!['amount'], 100);
  });

  test(
    'shifted checkpoint detects removed history even with replacement rows',
    () async {
      final server = SheetServer();
      server.rows.add(change('seed', item('travel', 100)).toRow());
      final phone = server.phone('one@example.com');
      addTearDown(phone.dispose);
      await phone.sync();
      await phone.finishApplication();
      server.rows[1] = change('replacement', item('travel', 900)).toRow();
      await expectLater(phone.sync(), throwsFormatException);
      expect(server.changeReadRanges.last, 'Changes!A:O');
      expect(phone.ledger.entities['transaction:travel']!['amount'], 100);
      expect(phone.pendingApplication, isNull);
    },
  );

  test('no-op shared polls do not rewrite the whole workspace', () async {
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

    expect(shared.restoreCount, 0);
    await app.syncSharedBudget();
    await app.syncSharedBudget();
    expect(shared.restoreCount, 0);

    final other = server.phone('two@example.com');
    addTearDown(other.dispose);
    await other.sync();
    await other.record(snapshot([item('travel', 900), item('refund', -100)]));
    await other.sync();

    await app.syncSharedBudget();
    expect(shared.restoreCount, 1);
    expect(app.transactions.firstWhere((tx) => tx.id == 'refund').amount, -100);
  });

  test(
    'active shared budget automatically uploads a newly added transaction',
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

      await app.addTransaction(item('new', 250));

      for (var i = 0; i < 100; i++) {
        final uploaded = server.rows.any(
          (row) => row.length > 1 && row[1] == 'transaction:new',
        );
        if (uploaded) break;
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(
        server.rows.where(
          (row) => row.length > 1 && row[1] == 'transaction:new',
        ),
        isNotEmpty,
      );
      expect(server.sheetTitles, contains('Transactions'));
      expect(
        server.transactionRows.where(
          (row) => row.isNotEmpty && row[0] == 'new',
        ),
        isNotEmpty,
      );
      expect(app.sharedSyncError, isNull);
    },
  );

  test('app applies shared data, preserves stale editor changes and returns to personal data', () async {
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
    await app.updateTransaction(item('travel', -800), revision: editorRevision);
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
  });
}
