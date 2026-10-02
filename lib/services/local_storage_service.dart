import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' hide Transaction;

import '../models/budget_category.dart';
import '../models/recurring_transaction.dart';
import '../models/savings_goal.dart';
import '../models/transaction.dart';

class LocalStorageService {
  final String workspaceId;
  LocalStorageService({this.workspaceId = ''});
  String get _prefix => workspaceId.isEmpty ? '' : 'shared_${workspaceId}_';
  String get _databaseName => workspaceId.isEmpty ? 'budget_tracker.db' : '${_prefix}budget_tracker.db';
  static const _databaseVersion = 3;
  static const _transactionsTable = 'transactions';

  String get _legacyTransactionsKey => '${_prefix}transactions_v2';
  String get _budgetKey => '${_prefix}monthly_budget_v2';
  String get _themeKey => '${_prefix}theme_mode_v1';
  String get _currencyKey => '${_prefix}currency_code_v1';
  String get _categoriesKey => '${_prefix}categories_v1';
  String get _goalsKey => '${_prefix}savings_goals_v1';
  String get _recurringTransactionsKey => '${_prefix}recurring_transactions_v1';
  String get _alertsEnabledKey => '${_prefix}budget_alerts_enabled_v1';
  String get _budgetCycleStartDayKey => '${_prefix}budget_cycle_start_day_v1';
  String get _backupFrequencyKey => '${_prefix}drive_backup_frequency_v1';
  String get _lastDriveBackupKey => '${_prefix}last_drive_backup_v1';
  String get _driveBackupDirtyKey => '${_prefix}drive_backup_dirty_v1';
  String get _alertStatePrefix => '${_prefix}budget_alert_state_';

  Database? _database;

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<Database> get _db async {
    if (_database != null) return _database!;
    final basePath = await getDatabasesPath();
    final database = await openDatabase(
      '$basePath/$_databaseName',
      version: _databaseVersion,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE $_transactionsTable (
            id TEXT PRIMARY KEY,
            store TEXT NOT NULL,
            amount REAL NOT NULL,
            category TEXT NOT NULL,
            date TEXT NOT NULL,
            note TEXT NOT NULL DEFAULT '',
            ledger TEXT NOT NULL DEFAULT '',
            account TEXT NOT NULL DEFAULT '',
            currency_code TEXT NOT NULL DEFAULT '',
            type TEXT NOT NULL DEFAULT 'expense'
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_transactions_date ON $_transactionsTable(date DESC)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "ALTER TABLE $_transactionsTable ADD COLUMN type TEXT NOT NULL DEFAULT 'expense'",
          );
        }
        if (oldVersion < 3) {
          await db.execute(
            "ALTER TABLE $_transactionsTable ADD COLUMN ledger TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE $_transactionsTable ADD COLUMN account TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE $_transactionsTable ADD COLUMN currency_code TEXT NOT NULL DEFAULT ''",
          );
        }
      },
    );
    _database = database;
    await _migrateLegacyTransactionsIfNeeded(database);
    return database;
  }

  Future<List<Transaction>> loadTransactions() async {
    final db = await _db;
    final rows = await db.query(_transactionsTable, orderBy: 'date DESC');
    return rows.map(_transactionFromRow).toList();
  }

  Future<void> insertTransaction(Transaction transaction) async {
    final db = await _db;
    await db.insert(
      _transactionsTable,
      _transactionToRow(transaction),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> insertTransactions(List<Transaction> transactions) async {
    if (transactions.isEmpty) return;
    final db = await _db;
    final batch = db.batch();
    for (final transaction in transactions) {
      batch.insert(
        _transactionsTable,
        _transactionToRow(transaction),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateTransaction(Transaction transaction) async {
    final db = await _db;
    await db.update(
      _transactionsTable,
      _transactionToRow(transaction),
      where: 'id = ?',
      whereArgs: [transaction.id],
    );
  }

  Future<void> renameTransactionCategory(String oldName, String newName) async {
    final db = await _db;
    await db.update(
      _transactionsTable,
      {'category': newName},
      where: 'category = ?',
      whereArgs: [oldName],
    );
  }

  Future<void> deleteTransaction(String id) async {
    final db = await _db;
    await db.delete(_transactionsTable, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearTransactions() async {
    final db = await _db;
    await db.delete(_transactionsTable);
  }

  Future<double> loadBudget() async {
    final prefs = await _prefs;
    return prefs.getDouble(_budgetKey) ?? 10000;
  }

  Future<void> saveBudget(double value) async {
    final prefs = await _prefs;
    await prefs.setDouble(_budgetKey, value);
  }

  Future<ThemeMode> loadThemeMode() async {
    final prefs = await _prefs;
    return switch (prefs.getString(_themeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await _prefs;
    await prefs.setString(_themeKey, mode.name);
  }

  Future<String> loadCurrencyCode() async {
    final prefs = await _prefs;
    return prefs.getString(_currencyKey) ?? 'EGP';
  }

  Future<void> saveCurrencyCode(String code) async {
    final prefs = await _prefs;
    await prefs.setString(_currencyKey, code);
  }

  Future<List<BudgetCategory>> loadCategories() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_categoriesKey);
    if (raw == null || raw.isEmpty) return BudgetCategory.defaults;
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final categories = decoded
          .map((item) => BudgetCategory.fromJson(item as Map<String, dynamic>))
          .toList();
      return categories.isEmpty ? BudgetCategory.defaults : categories;
    } catch (_) {
      return BudgetCategory.defaults;
    }
  }

  Future<void> saveCategories(List<BudgetCategory> categories) async {
    final prefs = await _prefs;
    await prefs.setString(
      _categoriesKey,
      jsonEncode(categories.map((item) => item.toJson()).toList()),
    );
  }

  Future<List<SavingsGoal>> loadGoals() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_goalsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((item) => SavingsGoal.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveGoals(List<SavingsGoal> goals) async {
    final prefs = await _prefs;
    await prefs.setString(
      _goalsKey,
      jsonEncode(goals.map((item) => item.toJson()).toList()),
    );
  }


  Future<List<RecurringTransaction>> loadRecurringTransactions() async {
    final prefs = await _prefs;
    final raw = prefs.getString(_recurringTransactionsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map(
            (item) => RecurringTransaction.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .where((item) => item.type.acceptsAmount(item.amount))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRecurringTransactions(
    List<RecurringTransaction> transactions,
  ) async {
    final prefs = await _prefs;
    await prefs.setString(
      _recurringTransactionsKey,
      jsonEncode(transactions.map((item) => item.toJson()).toList()),
    );
  }

  Future<bool> loadBudgetAlertsEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_alertsEnabledKey) ?? false;
  }

  Future<void> saveBudgetAlertsEnabled(bool value) async {
    final prefs = await _prefs;
    await prefs.setBool(_alertsEnabledKey, value);
  }

  Future<int> loadBudgetCycleStartDay() async {
    final prefs = await _prefs;
    return (prefs.getInt(_budgetCycleStartDayKey) ?? 1).clamp(1, 31).toInt();
  }

  Future<void> saveBudgetCycleStartDay(int value) async {
    final prefs = await _prefs;
    await prefs.setInt(_budgetCycleStartDayKey, value.clamp(1, 31).toInt());
  }

  Future<String> loadBackupFrequencyName() async {
    final prefs = await _prefs;
    return prefs.getString(_backupFrequencyKey) ?? 'off';
  }

  Future<void> saveBackupFrequencyName(String value) async {
    final prefs = await _prefs;
    await prefs.setString(_backupFrequencyKey, value);
  }

  Future<DateTime?> loadLastDriveBackupAt() async {
    final prefs = await _prefs;
    return DateTime.tryParse(prefs.getString(_lastDriveBackupKey) ?? '');
  }

  Future<void> saveLastDriveBackupAt(DateTime value) async {
    final prefs = await _prefs;
    await prefs.setString(_lastDriveBackupKey, value.toUtc().toIso8601String());
  }

  Future<bool> loadDriveBackupDirty() async {
    final prefs = await _prefs;
    return prefs.getBool(_driveBackupDirtyKey) ?? true;
  }

  Future<void> saveDriveBackupDirty(bool value) async {
    final prefs = await _prefs;
    await prefs.setBool(_driveBackupDirtyKey, value);
  }

  Future<Map<String, dynamic>> loadBudgetAlertState(String monthKey) async {
    final prefs = await _prefs;
    final raw = prefs.getString('$_alertStatePrefix$monthKey');
    if (raw == null || raw.isEmpty) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<void> saveBudgetAlertState(
    String monthKey,
    Map<String, dynamic> state,
  ) async {
    final prefs = await _prefs;
    await prefs.setString('$_alertStatePrefix$monthKey', jsonEncode(state));
  }

  Future<void> restoreFinancialSnapshot(Map<String, dynamic> data) async {
    final db = await _db;
    final rawTransactions = data['transactions'] as List<dynamic>? ?? const [];
    final transactions = rawTransactions
        .whereType<Map>()
        .map((item) => Transaction.fromJson(Map<String, dynamic>.from(item)))
        .toList();

    await db.transaction((txn) async {
      await txn.delete(_transactionsTable);
      for (final transaction in transactions) {
        await txn.insert(
          _transactionsTable,
          _transactionToRow(transaction),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });

    final prefs = await _prefs;
    final budget = (data['monthlyBudget'] as num?)?.toDouble();
    if (budget != null && budget > 0) {
      await prefs.setDouble(_budgetKey, budget);
    }

    final currency = data['currencyCode'] as String?;
    if (currency != null && currency.isNotEmpty) {
      await prefs.setString(_currencyKey, currency);
    }

    final theme = data['themeMode'] as String?;
    if (theme != null && theme.isNotEmpty) {
      await prefs.setString(_themeKey, theme);
    }

    final rawCategories = data['categories'] as List<dynamic>? ?? const [];
    if (rawCategories.isNotEmpty) {
      await prefs.setString(_categoriesKey, jsonEncode(rawCategories));
    } else {
      await prefs.remove(_categoriesKey);
    }

    final rawGoals = data['goals'] as List<dynamic>? ?? const [];
    await prefs.setString(_goalsKey, jsonEncode(rawGoals));

    final rawRecurring =
        data['recurringTransactions'] as List<dynamic>? ?? const [];
    await prefs.setString(
      _recurringTransactionsKey,
      jsonEncode(rawRecurring),
    );

    await prefs.setBool(
      _alertsEnabledKey,
      data['budgetAlertsEnabled'] as bool? ?? false,
    );
    await prefs.setInt(
      _budgetCycleStartDayKey,
      ((data['budgetCycleStartDay'] as num?)?.toInt() ?? 1).clamp(1, 31).toInt(),
    );

    for (final key in prefs.getKeys().where((key) => key.startsWith(_alertStatePrefix))) {
      await prefs.remove(key);
    }
  }

  Future<void> clearFinancialData() async {
    await clearTransactions();
    final prefs = await _prefs;
    await prefs.remove(_budgetKey);
    await prefs.remove(_currencyKey);
    await prefs.remove(_categoriesKey);
    await prefs.remove(_goalsKey);
    await prefs.remove(_recurringTransactionsKey);
    await prefs.remove(_alertsEnabledKey);
    await prefs.remove(_budgetCycleStartDayKey);
    for (final key in prefs.getKeys().where((key) => key.startsWith(_alertStatePrefix))) {
      await prefs.remove(key);
    }
  }

  Map<String, Object?> _transactionToRow(Transaction transaction) => {
        'id': transaction.id,
        'store': transaction.store,
        'amount': transaction.amount,
        'category': transaction.category,
        'date': transaction.date.toIso8601String(),
        'note': transaction.note,
        'ledger': transaction.ledger,
        'account': transaction.account,
        'currency_code': transaction.currencyCode,
        'type': transaction.type.name,
      };

  Transaction _transactionFromRow(Map<String, Object?> row) {
    return Transaction(
      id: row['id']! as String,
      store: row['store']! as String,
      amount: (row['amount']! as num).toDouble(),
      category: row['category']! as String,
      date: DateTime.parse(row['date']! as String),
      note: (row['note'] as String?) ?? '',
      ledger: (row['ledger'] as String?) ?? '',
      account: (row['account'] as String?) ?? '',
      currencyCode: (row['currency_code'] as String?) ?? '',
      type: TransactionType.fromName(row['type'] as String?),
    );
  }

  Future<void> _migrateLegacyTransactionsIfNeeded(Database db) async {
    final prefs = await _prefs;
    final raw = prefs.getString(_legacyTransactionsKey);
    if (raw == null || raw.isEmpty) return;

    try {
      final existingCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM $_transactionsTable'),
          ) ??
          0;
      if (existingCount == 0) {
        final decoded = jsonDecode(raw) as List<dynamic>;
        final batch = db.batch();
        for (final item in decoded) {
          final transaction = Transaction.fromJson(item as Map<String, dynamic>);
          batch.insert(
            _transactionsTable,
            _transactionToRow(transaction),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
        await batch.commit(noResult: true);
      }
      await prefs.remove(_legacyTransactionsKey);
    } catch (_) {
      // Leave legacy data untouched if migration fails so it is not lost.
    }
  }
}
