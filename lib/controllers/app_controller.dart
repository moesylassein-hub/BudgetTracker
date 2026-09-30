import 'package:flutter/material.dart';

import '../models/budget_category.dart';
import '../models/savings_goal.dart';
import '../models/transaction.dart';
import '../services/local_storage_service.dart';
import '../services/notification_service.dart';

class AppController extends ChangeNotifier {
  final LocalStorageService _storage;
  final NotificationService _notifications;

  AppController._(this._storage, this._notifications);

  final List<Transaction> _transactions = [];
  final List<BudgetCategory> _categories = [];
  final List<SavingsGoal> _goals = [];
  double _monthlyBudget = 10000;
  ThemeMode _themeMode = ThemeMode.system;
  String _currencyCode = 'EGP';
  bool _budgetAlertsEnabled = false;

  static Future<AppController> create(
    LocalStorageService storage,
    NotificationService notifications,
  ) async {
    final controller = AppController._(storage, notifications);
    await controller._load();
    await controller._checkBudgetAlerts();
    return controller;
  }

  List<Transaction> get transactions => List.unmodifiable(_transactions);
  List<BudgetCategory> get categories => List.unmodifiable(_categories);
  List<SavingsGoal> get goals => List.unmodifiable(_goals);
  double get monthlyBudget => _monthlyBudget;
  ThemeMode get themeMode => _themeMode;
  String get currencyCode => _currencyCode;
  bool get budgetAlertsEnabled => _budgetAlertsEnabled;

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
    return _transactions
        .where((item) => item.date.year == month.year && item.date.month == month.month)
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
    _monthlyBudget = await _storage.loadBudget();
    _themeMode = await _storage.loadThemeMode();
    _currencyCode = await _storage.loadCurrencyCode();
    _budgetAlertsEnabled = await _storage.loadBudgetAlertsEnabled();
    _sort();
  }

  Future<void> addTransaction(Transaction transaction) async {
    await _storage.insertTransaction(transaction);
    _transactions.add(transaction);
    _sort();
    notifyListeners();
    await _checkBudgetAlerts();
  }

  Future<void> updateTransaction(Transaction transaction) async {
    final index = _transactions.indexWhere((item) => item.id == transaction.id);
    if (index == -1) return;

    await _storage.updateTransaction(transaction);
    _transactions[index] = transaction;
    _sort();
    notifyListeners();
    await _checkBudgetAlerts();
  }

  Future<void> deleteTransaction(String id) async {
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
  }

  Future<void> setMonthlyBudget(double value) async {
    if (value <= 0) return;
    await _storage.saveBudget(value);
    _monthlyBudget = value;
    notifyListeners();
    await _checkBudgetAlerts();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _storage.saveThemeMode(mode);
    _themeMode = mode;
    notifyListeners();
  }

  Future<void> setCurrencyCode(String code) async {
    await _storage.saveCurrencyCode(code);
    _currencyCode = code;
    notifyListeners();
  }

  Future<bool> setBudgetAlertsEnabled(bool enabled) async {
    if (enabled) {
      final granted = await _notifications.requestPermission();
      if (!granted) return false;
    }
    await _storage.saveBudgetAlertsEnabled(enabled);
    _budgetAlertsEnabled = enabled;
    notifyListeners();
    if (enabled) await _checkBudgetAlerts();
    return true;
  }

  Future<void> addCategory(BudgetCategory category) async {
    _categories.add(category);
    await _storage.saveCategories(_categories);
    notifyListeners();
  }

  Future<void> updateCategory(BudgetCategory category) async {
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
    }
    _categories[index] = category;
    await _storage.saveCategories(_categories);
    notifyListeners();
    await _checkBudgetAlerts();
  }

  Future<bool> deleteCategory(String id) async {
    final matches = _categories.where((item) => item.id == id);
    if (matches.isEmpty) return false;
    final category = matches.first;
    if (categoriesForType(category.type).length <= 1) return false;
    if (_transactions.any((item) => item.category == category.name)) return false;
    _categories.removeWhere((item) => item.id == id);
    await _storage.saveCategories(_categories);
    notifyListeners();
    return true;
  }

  Future<void> addGoal(SavingsGoal goal) async {
    _goals.add(goal);
    await _storage.saveGoals(_goals);
    notifyListeners();
  }

  Future<void> updateGoal(SavingsGoal goal) async {
    final index = _goals.indexWhere((item) => item.id == goal.id);
    if (index == -1) return;
    _goals[index] = goal;
    await _storage.saveGoals(_goals);
    notifyListeners();
  }

  Future<void> deleteGoal(String id) async {
    _goals.removeWhere((item) => item.id == id);
    await _storage.saveGoals(_goals);
    notifyListeners();
  }

  Future<void> changeGoalSavings(String id, double delta) async {
    final index = _goals.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final current = _goals[index];
    final next = (current.savedAmount + delta).clamp(0.0, double.infinity).toDouble();
    _goals[index] = current.copyWith(savedAmount: next);
    await _storage.saveGoals(_goals);
    notifyListeners();
  }

  Future<void> clearAllData() async {
    await _storage.clearFinancialData();
    _transactions.clear();
    _categories
      ..clear()
      ..addAll(BudgetCategory.defaults);
    _goals.clear();
    _monthlyBudget = 10000;
    _currencyCode = 'EGP';
    _budgetAlertsEnabled = false;
    notifyListeners();
  }

  Future<void> _checkBudgetAlerts() async {
    if (!_budgetAlertsEnabled) return;
    final now = DateTime.now();
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
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
