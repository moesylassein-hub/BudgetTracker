import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

enum BackupFrequency {
  off,
  daily,
  weekly,
  monthly;

  String get label => switch (this) {
        BackupFrequency.off => 'Off',
        BackupFrequency.daily => 'Daily',
        BackupFrequency.weekly => 'Weekly',
        BackupFrequency.monthly => 'Monthly',
      };

  static BackupFrequency fromName(String? value) {
    return BackupFrequency.values.firstWhere(
      (item) => item.name == value,
      orElse: () => BackupFrequency.off,
    );
  }

  bool isDue(DateTime? lastBackup, DateTime now) {
    if (this == BackupFrequency.off) return false;
    if (lastBackup == null) return true;
    final last = lastBackup.toLocal();
    final current = now.toLocal();
    return switch (this) {
      BackupFrequency.off => false,
      BackupFrequency.daily => current.difference(last) >= const Duration(days: 1),
      BackupFrequency.weekly => current.difference(last) >= const Duration(days: 7),
      BackupFrequency.monthly => !current.isBefore(
          DateTime(
            last.year,
            last.month + 1,
            last.day.clamp(1, 28).toInt(),
            last.hour,
            last.minute,
          ),
        ),
    };
  }
}

class DriveBackupService {
  static const _scope = 'https://www.googleapis.com/auth/drive.appdata';
  // OAuth client IDs are public app identifiers, not client secrets.
  // Other deployments can supply their own ID, or an empty value to disable it.
  static const _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
    defaultValue: '360381329667-0h2jd9c82upiompn2usq2al5mtj82g79.apps.googleusercontent.com',
  );
  static const _filePrefix = 'budget_tracker_backup_';
  static const _maxBackups = 10;

  final GoogleSignIn _signIn = GoogleSignIn.instance;
  GoogleSignInAccount? _account;
  bool _initialized = false;

  bool get isConfigured => _serverClientId.isNotEmpty;
  bool get isConnected => _account != null;
  String? get accountEmail => _account?.email;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (!isConfigured) return;

    try {
      await _signIn.initialize(serverClientId: _serverClientId);
      final lightweight = _signIn.attemptLightweightAuthentication();
      if (lightweight != null) {
        _account = await lightweight;
      }
    } on GoogleSignInException {
      _account = null;
    }
  }

  Future<String> connect() async {
    if (!isConfigured) {
      throw StateError(
        'Google Drive is not configured. Build with GOOGLE_SERVER_CLIENT_ID.',
      );
    }
    await initialize();
    final account = await _signIn.authenticate(scopeHint: const [_scope]);
    await account.authorizationClient.authorizeScopes(const [_scope]);
    _account = account;
    return account.email;
  }

  Future<void> disconnect() async {
    if (!_initialized || !isConfigured) return;
    await _signIn.signOut();
    _account = null;
  }

  Future<Map<String, String>> sharedSheetHeaders({bool interactive = false}) async {
    await initialize();
    if (!isConfigured) throw StateError('Google sign-in is not configured.');
    var account = _account;
    if (account == null) {
      final lightweight = _signIn.attemptLightweightAuthentication();
      if (lightweight != null) account = await lightweight;
    }
    if (account == null && interactive) account = await _signIn.authenticate();
    if (account == null) throw StateError('Connect Google to sync this budget.');
    // Sheets scope allows invited users to open a shared spreadsheet by its URL.
    // drive.file is sufficient to create and share files created by this app.
    const scopes = [
      'https://www.googleapis.com/auth/spreadsheets',
      'https://www.googleapis.com/auth/drive.file',
    ];
    var headers = await account.authorizationClient.authorizationHeaders(
      scopes,
    );
    if (headers == null && interactive) {
      // Sheets/drive.file are additional scopes beyond the private Drive
      // backup scope. Request them explicitly from a user gesture, then read
      // the cached authorization headers for subsequent background syncs.
      await account.authorizationClient.authorizeScopes(scopes);
      headers = await account.authorizationClient.authorizationHeaders(scopes);
    }
    if (headers == null) {
      throw StateError(
        interactive
            ? 'Google Sheets permission was not granted. Try reconnecting.'
            : 'Reconnect Google to resume shared budget syncing.',
      );
    }
    _account = account;
    return headers;
  }

  Future<DateTime> uploadSnapshot(
    Map<String, dynamic> snapshot, {
    bool interactive = false,
  }) async {
    final headers = await _authorizationHeaders(interactive: interactive);
    if (headers == null) {
      throw StateError('Connect Google Drive before backing up.');
    }

    final now = DateTime.now().toUtc();
    final fileName = '$_filePrefix${_timestamp(now)}.json';
    final boundary = 'budget_tracker_${now.microsecondsSinceEpoch}';
    final metadata = jsonEncode({
      'name': fileName,
      'parents': ['appDataFolder'],
      'mimeType': 'application/json',
      'appProperties': {'kind': 'budget_tracker_backup', 'schema': '2'},
    });
    final data = jsonEncode(snapshot);
    final body = utf8.encode(
      '--$boundary\r\n'
      'Content-Type: application/json; charset=UTF-8\r\n\r\n'
      '$metadata\r\n'
      '--$boundary\r\n'
      'Content-Type: application/json; charset=UTF-8\r\n\r\n'
      '$data\r\n'
      '--$boundary--',
    );

    final response = await http.post(
      Uri.https(
        'www.googleapis.com',
        '/upload/drive/v3/files',
        {'uploadType': 'multipart', 'fields': 'id,name,modifiedTime'},
      ),
      headers: {
        ...headers,
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
      body: body,
    );
    _ensureSuccess(response, 'Google Drive backup');

    await _pruneOldBackups(headers);
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return DateTime.tryParse(decoded['modifiedTime'] as String? ?? '') ?? now;
  }

  Future<Map<String, dynamic>?> downloadLatestSnapshot({
    bool interactive = false,
  }) async {
    final headers = await _authorizationHeaders(interactive: interactive);
    if (headers == null) {
      throw StateError('Connect Google Drive before restoring.');
    }

    final backups = await _listBackups(headers, pageSize: 1);
    if (backups.isEmpty) return null;
    final id = backups.first['id'] as String?;
    if (id == null || id.isEmpty) return null;

    final response = await http.get(
      Uri.https('www.googleapis.com', '/drive/v3/files/$id', {'alt': 'media'}),
      headers: headers,
    );
    _ensureSuccess(response, 'Google Drive restore');

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map) {
      throw const FormatException('Backup file is not a valid Budget Tracker snapshot.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<Map<String, String>?> _authorizationHeaders({
    required bool interactive,
  }) async {
    await initialize();
    if (!isConfigured) return null;

    var account = _account;
    if (account == null) {
      final lightweight = _signIn.attemptLightweightAuthentication();
      if (lightweight != null) account = await lightweight;
    }

    if (account == null && interactive) {
      account = await _signIn.authenticate(scopeHint: const [_scope]);
    }
    if (account == null) return null;

    var headers = await account.authorizationClient.authorizationHeaders(
      const [_scope],
      promptIfNecessary: interactive,
    );
    if (headers == null && interactive) {
      await account.authorizationClient.authorizeScopes(const [_scope]);
      headers = await account.authorizationClient.authorizationHeaders(
        const [_scope],
      );
    }
    _account = account;
    return headers;
  }

  Future<List<Map<String, dynamic>>> _listBackups(
    Map<String, String> headers, {
    int pageSize = 20,
  }) async {
    final response = await http.get(
      Uri.https(
        'www.googleapis.com',
        '/drive/v3/files',
        {
          'spaces': 'appDataFolder',
          'q': "name contains '$_filePrefix'",
          'orderBy': 'modifiedTime desc',
          'pageSize': '$pageSize',
          'fields': 'files(id,name,modifiedTime,size)',
        },
      ),
      headers: headers,
    );
    _ensureSuccess(response, 'List Google Drive backups');

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return (decoded['files'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<void> _pruneOldBackups(Map<String, String> headers) async {
    final backups = await _listBackups(headers);
    for (final backup in backups.skip(_maxBackups)) {
      final id = backup['id'] as String?;
      if (id == null || id.isEmpty) continue;
      final response = await http.delete(
        Uri.https('www.googleapis.com', '/drive/v3/files/$id'),
        headers: headers,
      );
      _ensureSuccess(response, 'Delete old Google Drive backup');
    }
  }

  void _ensureSuccess(http.Response response, String action) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    var detail = '';
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['error'] is Map) {
        detail = (decoded['error'] as Map)['message']?.toString() ?? '';
      }
    } catch (_) {
      detail = '';
    }
    throw StateError(
      detail.isEmpty
          ? '$action failed (HTTP ${response.statusCode}).'
          : '$action failed: $detail',
    );
  }

  String _timestamp(DateTime value) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${value.year}${two(value.month)}${two(value.day)}_'
        '${two(value.hour)}${two(value.minute)}${two(value.second)}';
  }
}
