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
  DateTime? lastSynced;
  Map<String, dynamic>? pendingApplication;
  final ledger = SheetLedger();
  final List<SheetChange> pending = [];
  final Set<String> _seenIds = {};
  static const _activeKey = 'shared_sheet_active_v1';
  String get _stateKey => 'shared_sheet_state_v1_$sheetId';
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

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final active = prefs.getString(_activeKey);
    if (active == null) return;
    sheetId = parseId(active);
    final raw = prefs.getString(_stateKey);
    if (raw == null) {
      throw StateError('Shared budget cache is missing. Rejoin the Sheet.');
    }
    final data = jsonDecode(raw) as Map;
    title = data['title'] as String?;
    accountEmail = data['accountEmail'] as String?;
    lastSynced = DateTime.tryParse(data['lastSynced'] as String? ?? '');
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
  }

  Future<void> leave() async {
    if (pending.isNotEmpty) {
      throw StateError('Sync pending changes before switching budgets.');
    }
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
            'properties': {'sheetId': 1, 'title': 'Read me'},
          },
        ],
      },
    );
    final created = jsonDecode(response.body) as Map;
    sheetId = created['spreadsheetId'] as String;
    title = name.trim();
    accountEmail = email;
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
            'range': "'Read me'!A1:A7",
            'values': [
              ['Budget Tracker shared budget — format 1'],
              [
                'Share this spreadsheet with other Google accounts as Editors, then paste its link in Budget Tracker.',
              ],
              [
                'Changes keeps the revision history. Edit budgets normally in the app.',
              ],
              [
                'For direct Sheet edits, edit Date, Type, Merchant, Category, Amount, Note, Ledger, Account or Currency on the latest transaction revision.',
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
    final changes = ledger.edits(snapshot, email);
    ledger.addAll(changes);
    pending.addAll(changes);
    // Save the outbox before the first upload, so an interrupted upload is retryable.
    await persist();
    await sync(interactive: true);
  }

  Future<void> join(String input, String email) async {
    sheetId = parseId(input);
    accountEmail = email;
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
    final changes = ledger.edits(snapshot, accountEmail ?? 'Budget Tracker');
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
      author: accountEmail ?? 'Budget Tracker',
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
      author: accountEmail ?? 'Budget Tracker',
      value: value,
    );
    ledger.addAll([change]);
    pending.add(change);
    await persist();
  }

  Future<List<SheetChange>> _read({bool interactive = false}) async {
    final response = await _request(
      'GET',
      'sheets.googleapis.com',
      '/v4/spreadsheets/$sheetId/values/Changes!A:O',
      query: {
        'valueRenderOption': 'UNFORMATTED_VALUE',
        'dateTimeRenderOption': 'FORMATTED_STRING',
      },
      interactive: interactive,
    );
    final rows = (jsonDecode(response.body) as Map)['values'] as List? ?? [];
    if (rows.isEmpty ||
        canonicalJson(rows.first) != canonicalJson(SheetChange.columns)) {
      throw const FormatException(
        'This is not a Budget Tracker shared Sheet, or its headers were changed.',
      );
    }
    final changes = <String, SheetChange>{};
    for (var i = 1; i < rows.length; i++) {
      final row = rows[i] as List;
      if (row.every((cell) => '$cell'.isEmpty)) continue;
      try {
        final change = SheetChange.fromRow(row);
        final previous = changes[change.id];
        if (previous != null && previous.revision != change.revision) {
          throw const FormatException('Change IDs must be unique.');
        }
        changes[change.id] = change;
      } catch (error) {
        throw FormatException(
          'Fix row ${i + 1} in the shared Sheet before syncing: $error',
        );
      }
    }
    if (!_seenIds.every(changes.containsKey)) {
      throw const FormatException(
        'Shared history rows were removed. Restore them using Sheets version history; use Deleted to remove transactions.',
      );
    }
    return changes.values.toList();
  }

  void _merge(List<SheetChange> remote) {
    // Direct cell edits replace that row's cached hash. Pending app descendants
    // still reference the old hash and therefore remain concurrent branches.
    final byId = {for (final change in remote) change.id: change};
    final pendingRevisions = pending.map((change) => change.revision).toSet();
    ledger.changes.removeWhere(
      (revision, change) =>
          byId.containsKey(change.id) &&
          byId[change.id]!.revision != revision &&
          !pendingRevisions.contains(revision),
    );
    ledger.addAll(remote);
    _seenIds.addAll(byId.keys);
    pending.removeWhere(
      (change) => byId[change.id]?.revision == change.revision,
    );
  }

  Future<void> sync({
    bool interactive = false,
    Map<String, dynamic>? localSnapshot,
  }) async {
    Future<void> checkpoint() async {
      // Store downloaded state and its application marker together. A restart
      // must apply this state before interpreting the older database as edits.
      if (localSnapshot != null) {
        pendingApplication = ledger.snapshot(localSnapshot);
      }
      await persist();
    }

    final remote = await _read(interactive: interactive);
    _merge(remote);
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
        }
      }
      ledger.addAll(pending);
      await checkpoint();
      final upload = List<SheetChange>.of(pending);
      await _request(
        'POST',
        'sheets.googleapis.com',
        '/v4/spreadsheets/$sheetId/values/Changes!A:O:append',
        query: {'valueInputOption': 'RAW', 'insertDataOption': 'INSERT_ROWS'},
        body: {'values': upload.map((change) => change.toRow()).toList()},
      );
      // Re-read before acknowledging; a timeout can mean the append succeeded.
      _merge(await _read());
      await checkpoint();
    }
    lastSynced = DateTime.now();
    await persist();
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
