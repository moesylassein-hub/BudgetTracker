// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/budget_category.dart';
import '../models/recurring_transaction.dart';
import '../models/savings_goal.dart';
import '../models/transaction.dart';
import '../models/sheet_change.dart';
import '../services/drive_backup_service.dart';
import '../services/local_storage_service.dart';
import '../services/notification_service.dart';
import '../services/sheet_sync_service.dart';
import '../utils/budget_cycle.dart';

class AppController extends ChangeNotifier {
  LocalStorageService _storage;
  final LocalStorageService _personalStorage;
  final NotificationService _notifications;
  final DriveBackupService _driveBackup;
  LocalStorageService Function(String) _workspaceStorage =
      (id) => LocalStorageService(workspaceId: id);
  SheetSyncService Function()? _sharedServiceFactory;

  AppController._(LocalStorageService storage, this._notifications, this._driveBackup)
      : _storage = storage, _personalStorage = storage;

  SheetSyncService? _shared;
  Timer? _syncTimer;
  bool _syncBusy = false;
  bool _disposed = false;
  bool _syncQueued = false;
  bool _appActive = true;
  String? _syncError;
  Future<void> _operation = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _operation.then((_) async {
      if (_shared?.pendingApplication != null) await _applySharedSnapshot();
      return action();
    });
    _operation = next.then<void>((_) {}, onError: (Object error, StackTrace stack) {});
    return next;
  }

  bool get sharedBudgetActive => _shared != null;
  String? get sharedBudgetId => _shared?.sheetId;
  String get sharedBudgetName => _shared?.title ?? 'Personal budget';
  String? get sharedSheetUrl => _shared?.url;
  bool get sharedSyncBusy => _syncBusy;
  String? get sharedSyncError => _syncError;
  DateTime? get sharedLastSynced => _shared?.lastSynced;
  int get sharedPendingCount => _shared?.pending.length ?? 0;
  Map<String, List<SheetChange>> get sharedConflicts => _shared?.ledger.conflicts ?? {};
  String? sharedRevision(String entity) => _shared?.ledger.heads[entity]?.last.revision;

  Future<void> _applySharedSnapshot() async {
    final service = _shared!;
    final snapshot = service.pendingApplication ?? service.ledger.snapshot(_backupSnapshot());
    await service.beginApplication(snapshot);
    await _storage.restoreFinancialSnapshot(snapshot);
    await _load();
    await service.finishApplication();
  }

  Future<bool> _recordStaleEdit(String entity, Map<String, dynamic> value, String? revision) async {
    final service = _shared;
    if (service == null || revision == null || sharedRevision(entity) == revision) return false;
    await service.recordVersion(entity, value, revision);
    await _applySharedSnapshot();
    notifyListeners();
    _scheduleSync();
    return true;
  }

  void setAppActive(bool active) {
    _appActive = active;
    if (active) _scheduleSync();
  }

  void _scheduleSync() {
    if (_shared == null || !_appActive || _disposed || _syncQueued) return;
    _syncQueued = true;
    unawaited(syncSharedBudget().whenComplete(() => _syncQueued = false));
  }

  Future<void> _restoreSharedSelection() async {
    final service = _sharedServiceFactory?.call() ?? SheetSyncService(_driveBackup.sharedSheetHeaders);
    try {
      await service.restore();
      if (service.active) {
        _shared = service;
        _storage = _workspaceStorage(service.sheetId!);
      } else {
        service.dispose();
      }
    } catch (error) {
      service.dispose();
      _syncError = 'Could not open the shared budget: $error';
    }
  }

  Future<void> openSharedBudget({String? link, String? name}) => _serial(() async {
    if (_shared != null) throw StateError('Switch to your personal budget before opening another Sheet.');
    final service = _sharedServiceFactory?.call() ?? SheetSyncService(_driveBackup.sharedSheetHeaders);
    try {
      await _driveBackup.sharedSheetHeaders(interactive: true);
      final email = _driveBackup.accountEmail!;
      if (link != null) {
        await service.join(link, email);
      } else {
        if (name == null || name.trim().isEmpty) throw StateError('Enter a budget name.');
        await service.create(name, _backupSnapshot(), email);
      }
      final storage = _workspaceStorage(service.sheetId!);
      final snapshot = service.ledger.snapshot(_backupSnapshot());
      await storage.restoreFinancialSnapshot(snapshot);
      await service.persist(activate: true);
      _storage = storage;
      _shared = service;
      _syncError = null;
      await _load();
      notifyListeners();
      _startSyncTimer();
    } catch (_) {
      service.dispose();
      rethrow;
    }
  });

  Future<void> leaveSharedBudget() => _serial(() async {
    final service = _shared;
    if (service == null) return;
    await service.record(_backupSnapshot());
    await service.leave();
    _syncTimer?.cancel();
    _shared = null;
    service.dispose();
    _storage = _personalStorage;
    _syncError = null;
    await _load();
    notifyListeners();
  });

  Future<void> inviteSharedEditor(String email) => _serial(() async {
    if (_shared == null) throw StateError('Open a shared budget first.');
    await _shared!.invite(email);
  });

  Future<void> resolveSharedConflict(String entity, SheetChange choice) => _serial(() async {
    final service = _shared;
    if (service == null) return;
    await service.resolve(entity, choice);
    await _applySharedSnapshot();
    notifyListeners();
    _scheduleSync();
  });

  Future<void> syncSharedBudget({bool interactive = false}) => _serial(() async {
    final service = _shared;
    if (service == null || _disposed) return;
    _syncBusy = true;
    _syncError = null;
    notifyListeners();
    try {
      // Recover local edits even if the app stopped between a DB write and
      // recording its outbox. Local state is never replaced before journaling.
      if (interactive) {
        await _driveBackup.sharedSheetHeaders(interactive: true);
        service.accountEmail = _driveBackup.accountEmail;
      }
      await service.record(_backupSnapshot());
      await service.sync(interactive: interactive);
      await _applySharedSnapshot();
      await _processRecurringTransactions();
    } catch (error) {
      _syncError = 'Sync paused: $error';
    } finally {
      _syncBusy = false;
      if (!_disposed) notifyListeners();
    }
  });

  void _startSyncTimer() {
    _syncTimer?.cancel();
    if (_shared == null) return;
    _syncTimer = Timer.periodic(const Duration(seconds: 30), (_) => _scheduleSync());
  }

  @override
  void dispose() {
    _disposed = true;
    _syncTimer?.cancel();
    _shared?.dispose();
    super.dispose();
  }

  final List<Transaction> _transactions = [];
  final List<BudgetCategory> _categories = [];
  final List<SavingsGoal> _goals = [];
  final List<RecurringTransaction> _recurringTransactions = [];
  double _monthlyBudget = 10000;
  ThemeMode _themeMode = ThemeMode.system;
  String _currencyCode = 'EGP';
  bool _budgetAlertsEnabled = false;
  int _budgetCycleStartDay = 1;
  BackupFrequency _backupFrequency = BackupFrequency.off;
  DateTime? _lastDriveBackupAt;
  bool _backupInProgress = false;
  String? _backupError;

  static Future<AppController> create(
    LocalStorageService storage,
    NotificationService notifications,
    DriveBackupService driveBackup,
    {LocalStorageService Function(String)? workspaceStorage,
    SheetSyncService Function()? sharedServiceFactory,}
  ) async {
    final controller = AppController._(storage, notifications, driveBackup);
    if (workspaceStorage != null) controller._workspaceStorage = workspaceStorage;
    controller._sharedServiceFactory = sharedServiceFactory;
    await controller._restoreSharedSelection();
    await controller._load();
    if (controller._shared?.pendingApplication != null) {
      await controller._applySharedSnapshot();
    }
    return controller;
  }

  Future<void> addTransaction(Transaction transaction) => _serial(() => _addTransaction(transaction));
  Future<void> updateTransaction(Transaction transaction, {String? revision}) => _serial(() => _updateTransaction(transaction, revision: revision));
  Future<void> deleteTransaction(String id) => _serial(() => _deleteTransaction(id));
  Future<void> importTransactions(
    List<Transaction> transactions,
  ) => _serial(() => _importTransactions(transactions));
  Future<void> setMonthlyBudget(double value, {String? revision}) => _serial(() => _setMonthlyBudget(value, revision: revision));
  Future<void> setThemeMode(ThemeMode mode) => _serial(() => _setThemeMode(mode));
  Future<void> setCurrencyCode(String code, {String? revision}) => _serial(() => _setCurrencyCode(code, revision: revision));
  Future<bool> setBudgetAlertsEnabled(bool enabled) => _serial(() => _setBudgetAlertsEnabled(enabled));
  Future<void> setBudgetCycleStartDay(int value, {String? revision}) => _serial(() => _setBudgetCycleStartDay(value, revision: revision));
  Future<void> addCategory(BudgetCategory category) => _serial(() => _addCategory(category));
  Future<void> updateCategory(BudgetCategory category, {String? revision}) => _serial(() => _updateCategory(category, revision: revision));
  Future<bool> deleteCategory(String id) => _serial(() => _deleteCategory(id));
  Future<void> addGoal(SavingsGoal goal) => _serial(() => _addGoal(goal));
  Future<void> updateGoal(SavingsGoal goal, {String? revision}) => _serial(() => _updateGoal(goal, revision: revision));
  Future<void> deleteGoal(String id) => _serial(() => _deleteGoal(id));
  Future<void> changeGoalSavings(String id, double delta) => _serial(() => _changeGoalSavings(id, delta));
  Future<void> addRecurringTransaction(
    RecurringTransaction recurring,
  ) => _serial(() => _addRecurringTransaction(recurring));
  Future<void> updateRecurringTransaction(RecurringTransaction recurring, {String? revision}) => _serial(() => _updateRecurringTransaction(recurring, revision: revision));
  Future<void> setRecurringTransactionActive(
    String id,
    bool active,
  ) => _serial(() => _setRecurringTransactionActive(id, active));
  Future<void> deleteRecurringTransaction(String id) => _serial(() => _deleteRecurringTransaction(id));
  Future<int> processRecurringTransactions() => _serial(() => _processRecurringTransactions());
  Future<void> clearAllData() => _serial(() => _clearAllData());
  Future<bool> restoreLatestDriveBackup() => _serial(() => _restoreLatestDriveBackup());

  bool _startupFinished = false;

  Future<void> finishStartup() async {
    if (_startupFinished) return;
    _startupFinished = true;
    _startSyncTimer();
    _scheduleSync();

    // Financial catch-up should not depend on Google Play Services or
    // notification initialization.
    try {
      await processRecurringTransactions();
    } catch (_) {
      // Keep the app usable even if one recurring rule is malformed.
    }

    try {
      await _notifications.initialize();
      await _checkBudgetAlerts();
    } catch (_) {
      // Notifications are optional; startup must continue without them.
    }

    try {
      await _driveBackup.initialize();
      await maybeAutoBackup();
    } catch (_) {
      // Drive backup is optional and can be retried from Settings.
    }
  }

  List<Transaction> get transactions => List.unmodifiable(_transactions);

  List<String> get ledgerOptions => _uniqueTransactionValues(
        (item) => item.ledger,
      );

  List<String> get accountOptions => _uniqueTransactionValues(
        (item) => item.account,
      );

  List<String> _uniqueTransactionValues(
    String Function(Transaction item) selector,
  ) {
    final values = <String, String>{};
    for (final transaction in _transactions) {
      final value = selector(transaction).trim();
      if (value.isEmpty) continue;
      values.putIfAbsent(value.toLowerCase(), () => value);
    }
    final result = values.values.toList();
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }
  List<BudgetCategory> get categories => List.unmodifiable(_categories);
  List<SavingsGoal> get goals => List.unmodifiable(_goals);
  List<RecurringTransaction> get recurringTransactions =>
      List.unmodifiable(_recurringTransactions);
  int get activeRecurringCount =>
      _recurringTransactions.where((item) => item.isActive).length;
  double get monthlyBudget => _monthlyBudget;
  ThemeMode get themeMode => _themeMode;
  String get currencyCode => _currencyCode;
  bool get budgetAlertsEnabled => _budgetAlertsEnabled;
  int get budgetCycleStartDay => _budgetCycleStartDay;
  BackupFrequency get backupFrequency => _backupFrequency;
  DateTime? get lastDriveBackupAt => _lastDriveBackupAt;
  bool get backupInProgress => _backupInProgress;
  String? get backupError => _backupError;
  bool get driveBackupConfigured => _driveBackup.isConfigured;
  bool get driveBackupConnected => _driveBackup.isConnected;
  String? get driveAccountEmail => _driveBackup.accountEmail;

  DateTime budgetCycleStartFor(DateTime reference) =>
      BudgetCycle.startFor(reference, _budgetCycleStartDay);

  DateTime budgetCycleEndExclusiveFor(DateTime reference) =>
      BudgetCycle.endExclusiveFor(reference, _budgetCycleStartDay);

  DateTime get currentCycleStart => budgetCycleStartFor(DateTime.now());
  DateTime get currentCycleEndExclusive => budgetCycleEndExclusiveFor(DateTime.now());
  double get currentCycleProgress =>
      BudgetCycle.progress(DateTime.now(), _budgetCycleStartDay);

  List<BudgetCategory> categoriesForType(TransactionType type) =>
      _categories.where((item) => item.type == type).toList();

  BudgetCategory? categoryByName(String name) {
    for (final category in _categories) {
      if (category.name == name) return category;
    }
    return null;
  }

  String fallbackCategory(TransactionType type) {
    final preferred = type == TransactionType.expense ? 'Other' : 'Other Income';
    final match = categoriesForType(type).where((item) => item.name == preferred);
    if (match.isNotEmpty) return match.first.name;
    final available = categoriesForType(type);
    return available.isEmpty ? preferred : available.first.name;
  }

  List<Transaction> transactionsForMonth(DateTime month) {
    final start = budgetCycleStartFor(month);
    final end = budgetCycleEndExclusiveFor(month);
    return _transactions
        .where((item) => !item.date.isBefore(start) && item.date.isBefore(end))
        .toList();
  }

  List<Transaction> transactionsForDay(DateTime day) {
    return _transactions
        .where((item) =>
            item.date.year == day.year &&
            item.date.month == day.month &&
            item.date.day == day.day)
        .toList();
  }

  List<Transaction> get currentMonthTransactions => transactionsForMonth(DateTime.now());

  List<Transaction> expensesForMonth(DateTime month) =>
      transactionsForMonth(month).where((item) => item.isExpense).toList();

  List<Transaction> incomeForMonth(DateTime month) =>
      transactionsForMonth(month).where((item) => item.isIncome).toList();

  List<Transaction> get currentMonthExpenses => expensesForMonth(DateTime.now());
  List<Transaction> get currentMonthIncomeTransactions => incomeForMonth(DateTime.now());

  double spentForMonth(DateTime month) => expensesForMonth(month).fold(
        0,
        (sum, item) => sum + item.amount,
      );

  double incomeTotalForMonth(DateTime month) => incomeForMonth(month).fold(
        0,
        (sum, item) => sum + item.amount,
      );

  double get currentMonthSpent => spentForMonth(DateTime.now());
  double get currentMonthIncome => incomeTotalForMonth(DateTime.now());
  double get currentMonthNet => currentMonthIncome - currentMonthSpent;
  double get remaining => _monthlyBudget - currentMonthSpent;

  double categorySpent(String categoryName, DateTime month) {
    return expensesForMonth(month)
        .where((item) => item.category == categoryName)
        .fold(0, (sum, item) => sum + item.amount);
  }

  Future<void> _load() async {
    _transactions
      ..clear()
      ..addAll(await _storage.loadTransactions());
    _categories
      ..clear()
      ..addAll(await _storage.loadCategories());
    _goals
      ..clear()
      ..addAll(await _storage.loadGoals());
    _recurringTransactions
      ..clear()
      ..addAll(await _storage.loadRecurringTransactions());
    _monthlyBudget = await _storage.loadBudget();
    _themeMode = await _storage.loadThemeMode();
    _currencyCode = await _storage.loadCurrencyCode();
    _budgetAlertsEnabled = await _storage.loadBudgetAlertsEnabled();
    _budgetCycleStartDay = await _storage.loadBudgetCycleStartDay();
    _backupFrequency = BackupFrequency.fromName(
      await _storage.loadBackupFrequencyName(),
    );
    _lastDriveBackupAt = await _storage.loadLastDriveBackupAt();
    _sort();
  }

  Future<void> _addTransaction(Transaction transaction) async {
    await _storage.insertTransaction(transaction);
    _transactions.add(transaction);
    _sort();
    notifyListeners();
    await _checkBudgetAlerts();
    await _markBackupDirty();
  }

  Future<void> _updateTransaction(Transaction transaction, {String? revision}) async {
    if (await _recordStaleEdit('transaction:${transaction.id}', transaction.toJson(), revision)) return;
    final index = _transactions.indexWhere((item) => item.id == transaction.id);
    if (index == -1) return;

    await _storage.updateTransaction(transaction);
    _transactions[index] = transaction;
    _sort();
    notifyListeners();
    await _checkBudgetAlerts();
    await _markBackupDirty();
  }

  Future<void> _deleteTransaction(String id) async {
    final index = _transactions.indexWhere((item) => item.id == id);
    if (index == -1) return;

    final removed = _transactions.removeAt(index);
    notifyListeners();
    try {
      await _storage.deleteTransaction(id);
    } catch (_) {
      _transactions.add(removed);
      _sort();
      notifyListeners();
      rethrow;
    }
    await _markBackupDirty();
  }

  Future<void> _importTransactions(
    List<Transaction> transactions,
  ) async {
    if (transactions.isEmpty) return;

    final imported = <Transaction>[];
    var categoriesChanged = false;

    for (var i = 0; i < transactions.length; i++) {
      final item = transactions[i];
      var requested = item.category.trim();
      if (requested.isEmpty) {
        requested =
            item.isIncome ? 'Other Income' : 'Other';
      }

      BudgetCategory? matching;
      for (final category in _categories) {
        if (category.type == item.type &&
            category.name.toLowerCase() == requested.toLowerCase()) {
          matching = category;
          break;
        }
      }

      var resolvedName = matching?.name;
      if (resolvedName == null) {
        var candidate = requested;
        var suffix = 2;
        while (_categories.any(
          (category) =>
              category.name.toLowerCase() == candidate.toLowerCase() &&
              category.type != item.type,
        )) {
          candidate =
              requested + ' (' + item.type.label + (suffix == 2 ? '' : ' ' + suffix.toString()) + ')';
          suffix++;
        }

        final category = BudgetCategory(
          id: 'import-' +
              item.type.name +
              '-' +
              DateTime.now().microsecondsSinceEpoch.toString() +
              '-' +
              i.toString(),
          name: candidate,
          iconKey: item.isIncome ? 'income' : 'category',
          type: item.type,
        );
        _categories.add(category);
        resolvedName = category.name;
        categoriesChanged = true;
      }

      imported.add(
        item.copyWith(
          category: resolvedName,
          id: 'imported-' +
              DateTime.now().microsecondsSinceEpoch.toString() +
              '-' +
              i.toString(),
        ),
      );
    }

    await _storage.insertTransactions(imported);
    if (categoriesChanged) {
      await _storage.saveCategories(_categories);
    }
    _transactions.addAll(imported);
    _sort();
    notifyListeners();
    await _checkBudgetAlerts();
    await _markBackupDirty();
  }

  Future<void> _setMonthlyBudget(double value, {String? revision}) async {
    if (await _recordStaleEdit('setting:monthlyBudget', {'value': value}, revision)) return;
    if (value <= 0) return;
    await _storage.saveBudget(value);
    _monthlyBudget = value;
    notifyListeners();
    await _checkBudgetAlerts();
    await _markBackupDirty();
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    await _storage.saveThemeMode(mode);
    _themeMode = mode;
    notifyListeners();
    await _markBackupDirty();
  }

  Future<void> _setCurrencyCode(String code, {String? revision}) async {
    if (await _recordStaleEdit('setting:currencyCode', {'value': code}, revision)) return;
    await _storage.saveCurrencyCode(code);
    _currencyCode = code;
    notifyListeners();
    await _markBackupDirty();
  }

  Future<bool> _setBudgetAlertsEnabled(bool enabled) async {
    if (enabled) {
      final granted = await _notifications.requestPermission();
      if (!granted) return false;
    }
    await _storage.saveBudgetAlertsEnabled(enabled);
    _budgetAlertsEnabled = enabled;
    notifyListeners();
    if (enabled) await _checkBudgetAlerts();
    await _markBackupDirty();
    return true;
  }

  Future<void> _setBudgetCycleStartDay(int value, {String? revision}) async {
    if (await _recordStaleEdit('setting:budgetCycleStartDay', {'value': value}, revision)) return;
    final next = value.clamp(1, 31).toInt();
    if (next == _budgetCycleStartDay) return;
    await _storage.saveBudgetCycleStartDay(next);
    _budgetCycleStartDay = next;
    notifyListeners();
    await _checkBudgetAlerts();
    await _markBackupDirty();
  }

  Future<void> _addCategory(BudgetCategory category) async {
    _categories.add(category);
    await _storage.saveCategories(_categories);
    notifyListeners();
    await _markBackupDirty();
  }

  Future<void> _updateCategory(BudgetCategory category, {String? revision}) async {
    if (await _recordStaleEdit('category:${category.id}', category.toJson(), revision)) return;
    final index = _categories.indexWhere((item) => item.id == category.id);
    if (index == -1) return;
    final old = _categories[index];
    if (old.name != category.name) {
      await _storage.renameTransactionCategory(old.name, category.name);
      for (var i = 0; i < _transactions.length; i++) {
        if (_transactions[i].category == old.name) {
          _transactions[i] = _transactions[i].copyWith(category: category.name);
        }
      }
      for (var i = 0; i < _recurringTransactions.length; i++) {
        if (_recurringTransactions[i].category == old.name) {
          _recurringTransactions[i] = _recurringTransactions[i].copyWith(
            category: category.name,
          );
        }
      }
      await _storage.saveRecurringTransactions(_recurringTransactions);
    }
    _categories[index] = category;
    await _storage.saveCategories(_categories);
    notifyListeners();
    await _checkBudgetAlerts();
    await _markBackupDirty();
  }

  Future<bool> _deleteCategory(String id) async {
    final matches = _categories.where((item) => item.id == id);
    if (matches.isEmpty) return false;
    final category = matches.first;
    if (categoriesForType(category.type).length <= 1) return false;
    if (_transactions.any((item) => item.category == category.name)) return false;
    if (_recurringTransactions.any((item) => item.category == category.name)) {
      return false;
    }
    _categories.removeWhere((item) => item.id == id);
    await _storage.saveCategories(_categories);
    notifyListeners();
    await _markBackupDirty();
    return true;
  }

  Future<void> _addGoal(SavingsGoal goal) async {
    _goals.add(goal);
    await _storage.saveGoals(_goals);
    notifyListeners();
    await _markBackupDirty();
  }

  Future<void> _updateGoal(SavingsGoal goal, {String? revision}) async {
    if (await _recordStaleEdit('goal:${goal.id}', goal.toJson(), revision)) return;
    final index = _goals.indexWhere((item) => item.id == goal.id);
    if (index == -1) return;
    _goals[index] = goal;
    await _storage.saveGoals(_goals);
    notifyListeners();
    await _markBackupDirty();
  }

  Future<void> _deleteGoal(String id) async {
    _goals.removeWhere((item) => item.id == id);
    await _storage.saveGoals(_goals);
    notifyListeners();
    await _markBackupDirty();
  }

  Future<void> _changeGoalSavings(String id, double delta) async {
    final index = _goals.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final current = _goals[index];
    final next = (current.savedAmount + delta).clamp(0.0, double.infinity).toDouble();
    _goals[index] = current.copyWith(savedAmount: next);
    await _storage.saveGoals(_goals);
    notifyListeners();
    await _markBackupDirty();
  }

  Future<void> _addRecurringTransaction(
    RecurringTransaction recurring,
  ) async {
    _recurringTransactions.add(recurring);
    await _storage.saveRecurringTransactions(_recurringTransactions);
    notifyListeners();
    await _processRecurringTransactions();
    await _markBackupDirty();
  }

  Future<void> _updateRecurringTransaction(RecurringTransaction recurring, {String? revision}) async {
    if (await _recordStaleEdit('recurring:${recurring.id}', recurring.toJson(), revision)) return;
    final index =
        _recurringTransactions.indexWhere((item) => item.id == recurring.id);
    if (index == -1) return;
    _recurringTransactions[index] = recurring;
    await _storage.saveRecurringTransactions(_recurringTransactions);
    notifyListeners();
    await _processRecurringTransactions();
    await _markBackupDirty();
  }

  Future<void> _setRecurringTransactionActive(
    String id,
    bool active,
  ) async {
    final index = _recurringTransactions.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final current = _recurringTransactions[index];
    _recurringTransactions[index] = current.copyWith(
      isActive: active,
      lastGeneratedOn: active ? DateTime.now() : current.lastGeneratedOn,
    );
    await _storage.saveRecurringTransactions(_recurringTransactions);
    notifyListeners();
    await _markBackupDirty();
  }

  Future<void> _deleteRecurringTransaction(String id) async {
    _recurringTransactions.removeWhere((item) => item.id == id);
    await _storage.saveRecurringTransactions(_recurringTransactions);
    notifyListeners();
    await _markBackupDirty();
  }

  Future<int> _processRecurringTransactions() async {
    if (_recurringTransactions.isEmpty) return 0;

    final today = DateTime.now();
    var createdCount = 0;
    var rulesChanged = false;

    for (var i = 0; i < _recurringTransactions.length; i++) {
      final rule = _recurringTransactions[i];
      if (!rule.isActive) continue;

      final dueDates = rule.dueDatesThrough(today);
      if (dueDates.isEmpty) continue;

      var lastProcessed = rule.lastGeneratedOn;
      for (final dueDate in dueDates) {
        final transactionId = rule.occurrenceTransactionId(dueDate);
        final alreadyExists =
            _transactions.any((item) => item.id == transactionId);

        if (!alreadyExists) {
          final category = categoryByName(rule.category);
          final resolvedCategory =
              category != null && category.type == rule.type
                  ? category.name
                  : fallbackCategory(rule.type);
          final transaction = Transaction(
            id: transactionId,
            store: rule.title,
            amount: rule.amount,
            category: resolvedCategory,
            date: DateTime(
              dueDate.year,
              dueDate.month,
              dueDate.day,
              12,
            ),
            note: rule.note.trim().isEmpty
                ? 'Recurring • ${rule.frequency.label}'
                : rule.note.trim(),
            type: rule.type,
          );
          await _storage.insertTransaction(transaction);
          _transactions.add(transaction);
          createdCount++;
        }

        lastProcessed = dueDate;
      }

      if (lastProcessed != null &&
          lastProcessed != rule.lastGeneratedOn) {
        _recurringTransactions[i] = rule.copyWith(
          lastGeneratedOn: lastProcessed,
        );
        rulesChanged = true;
      }
    }

    if (rulesChanged) {
      await _storage.saveRecurringTransactions(_recurringTransactions);
    }
    if (createdCount > 0 || rulesChanged) {
      _sort();
      notifyListeners();
      await _checkBudgetAlerts();
      await _markBackupDirty();
    }
    return createdCount;
  }

  Future<void> _clearAllData() async {
    await _storage.clearFinancialData();
    _transactions.clear();
    _categories
      ..clear()
      ..addAll(BudgetCategory.defaults);
    _goals.clear();
    _recurringTransactions.clear();
    _monthlyBudget = 10000;
    _currencyCode = 'EGP';
    _budgetAlertsEnabled = false;
    _budgetCycleStartDay = 1;
    notifyListeners();
    await _markBackupDirty();
  }

  Future<void> connectDriveBackup() async {
    _backupError = null;
    try {
      await _driveBackup.connect();
      if (_backupFrequency == BackupFrequency.off) {
        _backupFrequency = BackupFrequency.daily;
        await _storage.saveBackupFrequencyName(_backupFrequency.name);
      }
      notifyListeners();
      await backupNow();
    } catch (error) {
      _backupError = error.toString();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> disconnectDriveBackup() async {
    await _driveBackup.disconnect();
    notifyListeners();
  }

  Future<void> setBackupFrequency(BackupFrequency frequency) async {
    _backupFrequency = frequency;
    await _storage.saveBackupFrequencyName(frequency.name);
    notifyListeners();
    if (frequency != BackupFrequency.off) {
      unawaited(maybeAutoBackup());
    }
  }

  Future<void> backupNow() async {
    await _performBackup(interactive: true);
  }

  Future<bool> _restoreLatestDriveBackup() async {
    if (_shared != null) throw StateError('Switch to your personal budget before restoring a backup.');
    _backupInProgress = true;
    _backupError = null;
    notifyListeners();
    try {
      final snapshot = await _driveBackup.downloadLatestSnapshot(interactive: true);
      if (snapshot == null) return false;
      await _storage.restoreFinancialSnapshot(snapshot);
      await _storage.saveDriveBackupDirty(false);
      await _load();
      await _checkBudgetAlerts();
      notifyListeners();
      return true;
    } catch (error) {
      _backupError = error.toString();
      notifyListeners();
      rethrow;
    } finally {
      _backupInProgress = false;
      notifyListeners();
    }
  }

  Future<void> maybeAutoBackup() async {
    if (_backupInProgress ||
        _backupFrequency == BackupFrequency.off ||
        !_driveBackup.isConnected) {
      return;
    }
    if (!await _storage.loadDriveBackupDirty()) return;
    if (!_backupFrequency.isDue(_lastDriveBackupAt, DateTime.now())) return;

    try {
      await _performBackup(interactive: false);
    } catch (error) {
      _backupError = error.toString();
      notifyListeners();
    }
  }

  Future<void> _performBackup({required bool interactive}) async {
    if (_backupInProgress) return;
    _backupInProgress = true;
    final storage = _storage;
    _backupError = null;
    notifyListeners();
    try {
      final uploadedAt = await _driveBackup.uploadSnapshot(
        _backupSnapshot(),
        interactive: interactive,
      );
      _lastDriveBackupAt = uploadedAt.toLocal();
      await storage.saveLastDriveBackupAt(uploadedAt);
      await storage.saveDriveBackupDirty(false);
    } catch (error) {
      _backupError = error.toString();
      rethrow;
    } finally {
      _backupInProgress = false;
      notifyListeners();
    }
  }

  Map<String, dynamic> _backupSnapshot() => {
        'schemaVersion': 2,
        'appVersion': '1.1.0',
        'generatedAt': DateTime.now().toUtc().toIso8601String(),
        'transactions': _transactions.map((item) => item.toJson()).toList(),
        'categories': _categories.map((item) => item.toJson()).toList(),
        'goals': _goals.map((item) => item.toJson()).toList(),
        'recurringTransactions':
            _recurringTransactions.map((item) => item.toJson()).toList(),
        'monthlyBudget': _monthlyBudget,
        'themeMode': _themeMode.name,
        'currencyCode': _currencyCode,
        'budgetAlertsEnabled': _budgetAlertsEnabled,
        'budgetCycleStartDay': _budgetCycleStartDay,
      };

  Future<void> _markBackupDirty() async {
    if (_shared != null) {
      await _shared!.record(_backupSnapshot());
      _scheduleSync();
    }
    await _storage.saveDriveBackupDirty(true);
    unawaited(maybeAutoBackup());
  }

  Future<void> _checkBudgetAlerts() async {
    if (!_budgetAlertsEnabled) return;
    final now = DateTime.now();
    final cycleStart = budgetCycleStartFor(now);
    final monthKey =
        'cycle-${cycleStart.year}-${cycleStart.month.toString().padLeft(2, '0')}-${cycleStart.day.toString().padLeft(2, '0')}';
    final state = await _storage.loadBudgetAlertState(monthKey);
    var overallThreshold = (state['overallThreshold'] as num?)?.toInt() ?? 0;
    final categoryIds = Set<String>.from(
      (state['categoryIds'] as List<dynamic>? ?? const []).map((item) => item.toString()),
    );

    if (_monthlyBudget > 0) {
      final percent = (currentMonthSpent / _monthlyBudget) * 100;
      final crossed = [50, 80, 100].where((threshold) => percent >= threshold).toList();
      if (crossed.isNotEmpty) {
        final highest = crossed.last;
        if (highest > overallThreshold) {
          overallThreshold = highest;
          await _notifications.showBudgetThreshold(
            percent: highest,
            spent: currentMonthSpent,
            budget: _monthlyBudget,
            currencyCode: _currencyCode,
          );
        }
      }
    }

    for (final category in _categories.where(
      (item) => item.type == TransactionType.expense && (item.monthlyBudget ?? 0) > 0,
    )) {
      final spent = categorySpent(category.name, now);
      final limit = category.monthlyBudget!;
      if (spent > limit && !categoryIds.contains(category.id)) {
        categoryIds.add(category.id);
        await _notifications.showCategoryExceeded(
          category: category.name,
          spent: spent,
          budget: limit,
          currencyCode: _currencyCode,
        );
      }
    }

    await _storage.saveBudgetAlertState(monthKey, {
      'overallThreshold': overallThreshold,
      'categoryIds': categoryIds.toList(),
    });
  }

  void _sort() => _transactions.sort((a, b) => b.date.compareTo(a.date));
}
