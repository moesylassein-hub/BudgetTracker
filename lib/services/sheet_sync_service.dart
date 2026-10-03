import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sheet_change.dart';

typedef SheetHeaders = Future<Map<String, String>> Function({bool interactive});

class SheetSyncService {
  final SheetHeaders headers;
  final http.Client client;
  SheetSyncService(this.headers, {http.Client? client})
    : client = client ?? http.Client();

  String? sheetId;
  String? title;
  String? accountEmail;
  String displayName = '';
  String get editor => displayName.isEmpty
      ? accountEmail ?? 'Unknown'
      : '$displayName <${accountEmail ?? 'Unknown'}>';

  Future<void> setAccount(String email) async {
    accountEmail = email;
    final prefs = await SharedPreferences.getInstance();
    displayName = prefs.getString('shared_editor_name_v1_$email') ?? '';
  }

  Future<void> setDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.length > 60 || trimmed.contains(RegExp(r'[<>\r\n]'))) {
      throw const FormatException(
        'Use a name up to 60 characters without angle brackets or line breaks.',
      );
    }
    if (accountEmail == null) throw StateError('Connect Google first.');
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      'shared_editor_name_v1_$accountEmail',
      trimmed,
    )) {
      throw StateError('Could not save your display name.');
    }
    displayName = trimmed;
  }

  DateTime? lastSynced;
  Map<String, dynamic>? pendingApplication;
  final ledger = SheetLedger();
  final List<SheetChange> pending = [];
  final Set<String> _seenIds = {};
  int _remoteRowCount = 0;
  DateTime? _lastFullReadAt;
  String? _transactionsViewHash;
  static const _fullHistoryRefreshInterval = Duration(minutes: 10);
  static const _transactionsViewColumns = [
    'ID',
    'Date',
    'Type',
    'Merchant',
    'Category',
    'Amount',
    'Note',
    'Ledger',
    'Account',
    'Currency',
  ];
  static const _activeKey = 'shared_sheet_active_v1';
  String get _stateKey => 'shared_sheet_state_v1_$sheetId';
  String get _lastSyncedKey => 'shared_sheet_last_synced_v1_$sheetId';
  bool get active => sheetId != null;
  String get url => 'https://docs.google.com/spreadsheets/d/$sheetId/edit';

  static String parseId(String input) {
    final uri = Uri.tryParse(input.trim());
    final id = uri != null && uri.host == 'docs.google.com'
        ? RegExp(
            r'^/spreadsheets/d/([a-zA-Z0-9_-]+)',
          ).firstMatch(uri.path)?.group(1)
        : input.trim();
    if (id == null || !RegExp(r'^[a-zA-Z0-9_-]{20,}$').hasMatch(id)) {
      throw const FormatException('Paste a Google Sheets sharing link.');
    }
    return id;
  }

  Future<void> restore({String? sheet}) async {
    final prefs = await SharedPreferences.getInstance();
    final active = sheet ?? prefs.getString(_activeKey);
    if (active == null) return;
    sheetId = parseId(active);
    final raw = prefs.getString(_stateKey);
    if (raw == null) {
      if (sheet != null) return;
      throw StateError('Shared budget cache is missing. Rejoin the Sheet.');
    }
    final data = jsonDecode(raw) as Map;
    title = data['title'] as String?;
    final email = data['accountEmail'] as String?;
    if (email != null) await setAccount(email);
    lastSynced = DateTime.tryParse(
      prefs.getString(_lastSyncedKey) ??
          data['lastSynced'] as String? ??
          '',
    );
    pendingApplication = data['application'] == null
        ? null
        : Map<String, dynamic>.from(data['application'] as Map);
    ledger.addAll(
      (data['changes'] as List).map(
        (raw) => SheetChange.fromJson(Map<String, dynamic>.from(raw as Map)),
      ),
    );
    pending.addAll(
      (data['pending'] as List).map(
        (raw) => SheetChange.fromJson(Map<String, dynamic>.from(raw as Map)),
      ),
    );
    _seenIds.addAll((data['seen'] as List).cast<String>());
  }

  Future<void> persist({bool activate = false}) async {
    if (!active) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      _stateKey,
      jsonEncode({
        'title': title,
        'accountEmail': accountEmail,
        'lastSynced': lastSynced?.toIso8601String(),
        'changes': ledger.changes.values
            .map((change) => change.toJson())
            .toList(),
        'pending': pending.map((change) => change.toJson()).toList(),
        'seen': _seenIds.toList(),
        'application': pendingApplication,
      }),
    );
    if (!saved) {
      throw StateError('Could not save pending shared changes on this phone.');
    }
    if (activate && !await prefs.setString(_activeKey, sheetId!)) {
      throw StateError('Could not save the shared budget selection.');
    }
    if (lastSynced != null) {
      await prefs.setString(_lastSyncedKey, lastSynced!.toIso8601String());
    }
  }

  Future<void> _persistLastSynced() async {
    if (!active || lastSynced == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      _lastSyncedKey,
      lastSynced!.toIso8601String(),
    )) {
      throw StateError('Could not save shared sync time on this phone.');
    }
  }

  Future<void> discardPending() async {
    final revisions = pending.map((change) => change.revision).toSet();
    ledger.changes.removeWhere((revision, _) => revisions.contains(revision));
    pending.clear();
    pendingApplication = null;
    await persist();
  }

  Future<void> leave() async {
    // Detach locally even if access was revoked. Keep the outbox for rejoining.
    await persist();
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(_activeKey)) {
      throw StateError('Could not switch to personal budget.');
    }
  }

  Future<void> beginApplication(Map<String, dynamic> snapshot) async {
    pendingApplication = snapshot;
    await persist();
  }

  Future<void> finishApplication() async {
    pendingApplication = null;
    await persist();
  }

  Future<http.Response> _request(
    String method,
    String host,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool interactive = false,
  }) async {
    final auth = await headers(interactive: interactive);
    final response = await client
        .send(
          http.Request(method, Uri.https(host, path, query))
            ..headers.addAll({...auth, 'Content-Type': 'application/json'})
            ..body = body == null ? '' : jsonEncode(body),
        )
        .timeout(const Duration(seconds: 25));
    final result = await http.Response.fromStream(
      response,
    ).timeout(const Duration(seconds: 25));
    if (result.statusCode < 200 || result.statusCode >= 300) {
      if (result.statusCode == 401) {
        throw StateError('Reconnect Google to resume syncing.');
      }
      if (result.statusCode == 403) {
        throw StateError(
          'Google denied access. Enable the Sheets API, allow this account as a test user, and check Sheet editing access.',
        );
      }
      if (result.statusCode == 404) {
        throw StateError(
          'Sheet not found or not shared with this Google account.',
        );
      }
      if (result.statusCode == 429) {
        throw StateError(
          'Google is busy. Your edits are saved locally; try syncing later.',
        );
      }
      throw StateError(
        'Google Sheets request failed (${result.statusCode}). Your local changes are retained.',
      );
    }
    return result;
  }

  Future<void> create(
    String name,
    Map<String, dynamic> snapshot,
    String email,
  ) async {
    final response = await _request(
      'POST',
      'sheets.googleapis.com',
      '/v4/spreadsheets',
      interactive: true,
      body: {
        'properties': {'title': name.trim()},
        'sheets': [
          {
            'properties': {
              'sheetId': 0,
              'title': 'Changes',
              'gridProperties': {'frozenRowCount': 1},
            },
          },
          {
            'properties': {
              'sheetId': 1,
              'title': 'Transactions',
              'gridProperties': {'frozenRowCount': 1},
            },
          },
          {
            'properties': {'sheetId': 2, 'title': 'Read me'},
          },
        ],
      },
    );
    final created = jsonDecode(response.body) as Map;
    sheetId = created['spreadsheetId'] as String;
    title = name.trim();
    await setAccount(email);
    await _request(
      'POST',
      'sheets.googleapis.com',
      '/v4/spreadsheets/$sheetId/values:batchUpdate',
      body: {
        'valueInputOption': 'RAW',
        'data': [
          {
            'range': 'Changes!A1:O1',
            'values': [SheetChange.columns],
          },
          {
            'range': 'Transactions!A1:J1',
            'values': [_transactionsViewColumns],
          },
          {
            'range': "'Read me'!A1:A8",
            'values': [
              ['Budget Tracker shared budget — format 2'],
              [
                'Share this spreadsheet with other Google accounts as Editors, then paste its link in Budget Tracker.',
              ],
              [
                'Transactions is the current shared-budget view and is refreshed automatically by the app.',
              ],
              [
                'Changes keeps the append-only revision history used for syncing, offline edits and conflicts.',
              ],
              [
                'For direct Sheet edits, edit Date, Type, Merchant, Category, Amount, Note, Ledger, Account or Currency on the latest transaction revision in Changes.',
              ],
              [
                'Use TRUE in Deleted to delete a transaction. Do not remove history rows or change IDs, Item or Replaces.',
              ],
              [
                'Date uses ISO format (for example 2026-10-02T12:00:00). Type is expense or income. Negative expenses are refunds.',
              ],
              [
                'Sync checks for conflicts. Resolve differing versions in Settings → Shared budget.',
              ],
            ],
          },
        ],
      },
    );
    final changes = ledger.edits(snapshot, editor);
    ledger.addAll(changes);
    pending.addAll(changes);
    // Save the outbox before the first upload, so an interrupted upload is retryable.
    await persist();
    await sync(interactive: true);
  }

  Future<void> join(String input, String email) async {
    sheetId = parseId(input);
    await restore(sheet: sheetId);
    await setAccount(email);
    await sync(interactive: true);
    final metadata = await _request(
      'GET',
      'sheets.googleapis.com',
      '/v4/spreadsheets/$sheetId',
      query: {'fields': 'properties(title)'},
      interactive: true,
    );
    title = (jsonDecode(metadata.body) as Map)['properties']['title'] as String;
    await persist();
  }

  Future<void> record(Map<String, dynamic> snapshot) async {
    final changes = ledger.edits(snapshot, editor);
    if (changes.isEmpty) return;
    ledger.addAll(changes);
    pending.addAll(changes);
    await persist();
  }

  Future<void> resolve(String entity, SheetChange choice) async {
    final heads = ledger.heads[entity] ?? [];
    if (!heads.any((change) => change.revision == choice.revision)) {
      throw StateError('This conflict changed. Refresh and choose again.');
    }
    final change = SheetChange(
      id: newChangeId(),
      entity: entity,
      parents: heads.map((head) => head.revision).toList()..sort(),
      author: editor,
      value: choice.value,
    );
    ledger.addAll([change]);
    pending.add(change);
    await persist();
  }

  Future<void> recordVersion(
    String entity,
    Map<String, dynamic> value,
    String parent,
  ) async {
    final change = SheetChange(
      id: newChangeId(),
      entity: entity,
      parents: [parent],
      author: editor,
      value: value,
    );
    ledger.addAll([change]);
    pending.add(change);
    await persist();
  }

  Future<List<SheetChange>> _read({bool interactive = false}) async {
    final now = DateTime.now();
    final fullRead =
        interactive ||
        _remoteRowCount == 0 ||
        _lastFullReadAt == null ||
        now.difference(_lastFullReadAt!) >= _fullHistoryRefreshInterval;
    final firstRow = fullRead ? 1 : _remoteRowCount + 1;
    final range = fullRead
        ? 'Changes!A:O'
        : 'Changes!A$firstRow:O';
    final response = await _request(
      'GET',
      'sheets.googleapis.com',
      '/v4/spreadsheets/$sheetId/values/$range',
      query: {
        'valueRenderOption': 'UNFORMATTED_VALUE',
        'dateTimeRenderOption': 'FORMATTED_STRING',
      },
      interactive: interactive,
    );
    final rows = (jsonDecode(response.body) as Map)['values'] as List? ?? [];

    if (fullRead) {
      if (rows.isEmpty ||
          canonicalJson(rows.first) != canonicalJson(SheetChange.columns)) {
        throw const FormatException(
          'This is not a Budget Tracker shared Sheet, or its headers were changed.',
        );
      }
    } else if (rows.isEmpty) {
      return const [];
    }

    final changes = <String, SheetChange>{};
    final startIndex = fullRead ? 1 : 0;
    for (var i = startIndex; i < rows.length; i++) {
      final row = rows[i] as List;
      if (row.every((cell) => '$cell'.isEmpty)) continue;
      final sheetRow = fullRead ? i + 1 : firstRow + i;
      try {
        final change = SheetChange.fromRow(row);
        final previous = changes[change.id];
        if (previous != null && previous.revision != change.revision) {
          throw const FormatException('Change IDs must be unique.');
        }
        if (!fullRead &&
            _seenIds.contains(change.id) &&
            ledger.changes[change.revision] == null) {
          throw const FormatException('Change IDs must be unique.');
        }
        changes[change.id] = change;
      } catch (error) {
        throw FormatException(
          'Fix row $sheetRow in the shared Sheet before syncing: $error',
        );
      }
    }

    if (fullRead) {
      if (!_seenIds.every(changes.containsKey)) {
        throw const FormatException(
          'Shared history rows were removed. Restore them using Sheets version history; use Deleted to remove transactions.',
        );
      }
      _remoteRowCount = rows.length;
      _lastFullReadAt = now;
    } else {
      _remoteRowCount += rows.length;
    }
    return changes.values.toList();
  }

  ({bool headsChanged, bool cacheChanged}) _merge(
    List<SheetChange> remote,
  ) {
    if (remote.isEmpty) {
      return (headsChanged: false, cacheChanged: false);
    }

    // New remote revisions can change the current shared state. Revisions that
    // are already in the local ledger are normally acknowledgements of our
    // own persisted outbox and do not require rewriting the local database.
    var headsChanged = remote.any(
      (change) => !ledger.changes.containsKey(change.revision),
    );
    var cacheChanged = headsChanged;
    final byId = {for (final change in remote) change.id: change};
    final pendingRevisions = pending.map((change) => change.revision).toSet();
    final beforeChanges = ledger.changes.length;
    ledger.changes.removeWhere(
      (revision, change) =>
          byId.containsKey(change.id) &&
          byId[change.id]!.revision != revision &&
          !pendingRevisions.contains(revision),
    );
    if (ledger.changes.length != beforeChanges) {
      cacheChanged = true;
      headsChanged = true;
    }

    ledger.addAll(remote);
    for (final id in byId.keys) {
      if (_seenIds.add(id)) cacheChanged = true;
    }
    final pendingBefore = pending.length;
    pending.removeWhere(
      (change) => byId[change.id]?.revision == change.revision,
    );
    if (pending.length != pendingBefore) cacheChanged = true;
    return (headsChanged: headsChanged, cacheChanged: cacheChanged);
  }

  Future<Set<String>> _sheetTitles({bool interactive = false}) async {
    final response = await _request(
      'GET',
      'sheets.googleapis.com',
      '/v4/spreadsheets/$sheetId',
      interactive: interactive,
      query: {'fields': 'sheets.properties.title'},
    );
    final decoded = jsonDecode(response.body) as Map;
    return ((decoded['sheets'] as List?) ?? const [])
        .whereType<Map>()
        .map((sheet) => sheet['properties'])
        .whereType<Map>()
        .map((properties) => properties['title']?.toString() ?? '')
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  Future<void> _ensureTransactionsSheet({
    bool interactive = false,
  }) async {
    final titles = await _sheetTitles(interactive: interactive);
    if (titles.contains('Transactions')) return;

    try {
      await _request(
        'POST',
        'sheets.googleapis.com',
        '/v4/spreadsheets/$sheetId:batchUpdate',
        interactive: interactive,
        body: {
          'requests': [
            {
              'addSheet': {
                'properties': {
                  'title': 'Transactions',
                  'gridProperties': {'frozenRowCount': 1},
                },
              },
            },
          ],
        },
      );
    } catch (_) {
      // Another editor can create the mirror tab between our metadata read and
      // addSheet request. Treat that race as success when the tab now exists.
      final refreshed = await _sheetTitles(interactive: interactive);
      if (!refreshed.contains('Transactions')) rethrow;
    }
  }

  List<List<Object>> _transactionsViewRows() {
    final values = ledger.entities.entries
        .where((entry) => entry.key.startsWith('transaction:'))
        .map((entry) {
          final value = entry.value;
          return <String, dynamic>{
            'id': value['id']?.toString() ??
                entry.key.substring('transaction:'.length),
            'date': value['date']?.toString() ?? '',
            'type': value['type']?.toString() ?? '',
            'store': value['store']?.toString() ?? '',
            'category': value['category']?.toString() ?? '',
            'amount': value['amount'],
            'note': value['note']?.toString() ?? '',
            'ledger': value['ledger']?.toString() ?? '',
            'account': value['account']?.toString() ?? '',
            'currencyCode': value['currencyCode']?.toString() ?? '',
          };
        })
        .toList()
      ..sort((a, b) {
        final byDate = (b['date'] as String).compareTo(a['date'] as String);
        if (byDate != 0) return byDate;
        return (a['id'] as String).compareTo(b['id'] as String);
      });

    return [
      List<Object>.from(_transactionsViewColumns),
      for (final value in values)
        [
          value['id'] as String,
          value['date'] as String,
          value['type'] as String,
          value['store'] as String,
          value['category'] as String,
          value['amount'] ?? '',
          value['note'] as String,
          value['ledger'] as String,
          value['account'] as String,
          value['currencyCode'] as String,
        ],
    ];
  }

  Future<void> _publishTransactionsView({
    bool interactive = false,
  }) async {
    final rows = _transactionsViewRows();
    final nextHash = canonicalJson(rows);
    if (_transactionsViewHash == nextHash) return;

    await _ensureTransactionsSheet(interactive: interactive);
    await _request(
      'POST',
      'sheets.googleapis.com',
      '/v4/spreadsheets/$sheetId/values:batchClear',
      interactive: interactive,
      body: {
        'ranges': ['Transactions!A:J'],
      },
    );
    await _request(
      'POST',
      'sheets.googleapis.com',
      '/v4/spreadsheets/$sheetId/values:batchUpdate',
      interactive: interactive,
      body: {
        'valueInputOption': 'RAW',
        'data': [
          {
            'range': 'Transactions!A1:J${rows.length}',
            'values': rows,
          },
        ],
      },
    );
    _transactionsViewHash = nextHash;
  }

  Future<void> sync({
    bool interactive = false,
    Map<String, dynamic>? localSnapshot,
  }) async {
    var cacheChanged = false;
    var needsApplication = false;

    Future<void> checkpoint() async {
      if (needsApplication && localSnapshot != null) {
        pendingApplication = ledger.snapshot(localSnapshot);
        cacheChanged = true;
      }
      if (cacheChanged) {
        await persist();
        cacheChanged = false;
      }
      needsApplication = false;
    }

    final remote = await _read(interactive: interactive);
    final firstMerge = _merge(remote);
    cacheChanged = cacheChanged || firstMerge.cacheChanged;
    needsApplication = needsApplication || firstMerge.headsChanged;
    await checkpoint();

    if (pending.isNotEmpty) {
      // Never reuse a remotely edited row ID after an uncertain upload.
      final remoteIds = remote.map((change) => change.id).toSet();
      final rewritten = <String, String>{};
      final oldPending = List<SheetChange>.of(pending);
      for (var i = 0; i < pending.length; i++) {
        final old = pending[i];
        if (remoteIds.contains(old.id) ||
            old.parents.any(rewritten.containsKey)) {
          final replacement = SheetChange(
            id: remoteIds.contains(old.id) ? newChangeId() : old.id,
            entity: old.entity,
            parents: old.parents
                .map((parent) => rewritten[parent] ?? parent)
                .toList(),
            author: old.author,
            value: old.value,
          );
          rewritten[old.revision] = replacement.revision;
          pending[i] = replacement;
        }
      }
      for (final old in oldPending) {
        if (rewritten.containsKey(old.revision)) {
          ledger.changes.remove(old.revision);
          cacheChanged = true;
        }
      }
      ledger.addAll(pending);
      if (rewritten.isNotEmpty) cacheChanged = true;
      await checkpoint();

      final upload = List<SheetChange>.of(pending);
      await _request(
        'POST',
        'sheets.googleapis.com',
        '/v4/spreadsheets/$sheetId/values/Changes!A:O:append',
        query: {'valueInputOption': 'RAW', 'insertDataOption': 'INSERT_ROWS'},
        body: {'values': upload.map((change) => change.toRow()).toList()},
      );

      // Only read rows appended since our cursor. If the append response was
      // lost after Google committed it, the next retry starts from the same
      // cursor and acknowledges those rows without duplicating them.
      final acknowledgement = _merge(await _read());
      cacheChanged = cacheChanged || acknowledgement.cacheChanged;
      needsApplication = needsApplication || acknowledgement.headsChanged;
      await checkpoint();
    }

    // Changes remains the authoritative append-only history. Transactions is
    // a readable current-state mirror so additions are immediately visible in
    // Google Sheets without decoding revision rows.
    await _publishTransactionsView(interactive: interactive);
    lastSynced = DateTime.now();
    await _persistLastSynced();
  }

  Future<void> invite(String email) async {
    final trimmed = email.trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(trimmed)) {
      throw const FormatException('Enter a valid Google account email.');
    }
    await _request(
      'POST',
      'www.googleapis.com',
      '/drive/v3/files/$sheetId/permissions',
      interactive: true,
      query: {'sendNotificationEmail': 'true'},
      body: {'type': 'user', 'role': 'writer', 'emailAddress': trimmed},
    );
  }

  void dispose() => client.close();
}
