import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quick_actions/quick_actions.dart';

import '../controllers/app_controller.dart';
import '../models/receipt_scan_result.dart';
import '../models/transaction.dart';
import 'add_transaction.dart';
import 'dashboard.dart';
import 'savings_goals.dart';
import 'scan_receipt.dart';
import 'settings.dart';
import 'reports.dart';
import 'transactions.dart';
import 'shared_budget.dart';

class HomeShell extends StatefulWidget {
  final AppController controller;

  const HomeShell({super.key, required this.controller});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const _quickActions = QuickActions();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_refresh);
    unawaited(_setupQuickActions());
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refresh);
    super.dispose();
  }

  Future<void> _setupQuickActions() async {
    await _quickActions.initialize((shortcutType) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (shortcutType) {
          case 'add_expense':
            _addTransaction(initialType: TransactionType.expense);
            break;
          case 'add_income':
            _addTransaction(initialType: TransactionType.income);
            break;
          case 'scan_receipt':
            _scanReceipt();
            break;
        }
      });
    });

    await _quickActions.setShortcutItems(const [
      ShortcutItem(type: 'add_expense', localizedTitle: 'Add expense'),
      ShortcutItem(type: 'add_income', localizedTitle: 'Add income'),
      ShortcutItem(type: 'scan_receipt', localizedTitle: 'Scan receipt'),
    ]);
  }

  Future<void> _addTransaction({
    ReceiptScanResult? scan,
    TransactionType initialType = TransactionType.expense,
  }) async {
    final transaction = await Navigator.of(context).push<Transaction>(
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(
          controller: widget.controller,
          scanResult: scan,
          initialType: initialType,
        ),
      ),
    );
    if (transaction != null) {
      await widget.controller.addTransaction(transaction);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${transaction.type.label} saved.')),
        );
      }
    }
  }

  Future<void> _scanReceipt() async {
    final result = await Navigator.of(context).push<ReceiptScanResult>(
      MaterialPageRoute(
        builder: (_) => ScanReceiptScreen(
          preferredCurrencyCode: widget.controller.currencyCode,
        ),
      ),
    );
    if (result != null && mounted) {
      await _addTransaction(scan: result, initialType: TransactionType.expense);
    }
  }

  Future<void> _editTransaction(Transaction transaction) async {
    final updated = await Navigator.of(context).push<Transaction>(
      MaterialPageRoute(
        builder: (_) => AddTransactionScreen(
          controller: widget.controller,
          transaction: transaction,
          initialType: transaction.type,
        ),
      ),
    );
    if (updated != null) await widget.controller.updateTransaction(updated);
  }

  Future<void> _showAddMenu() async {
    final type = await showModalBottomSheet<TransactionType>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.remove_circle_outline_rounded),
                title: const Text('Add expense', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Purchase, bill, transport, food and more'),
                onTap: () => Navigator.pop(sheetContext, TransactionType.expense),
              ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline_rounded),
                title: const Text('Add income', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Salary, freelance, refund, gift and more'),
                onTap: () => Navigator.pop(sheetContext, TransactionType.income),
              ),
              ListTile(
                leading: const Icon(Icons.document_scanner_rounded),
                title: const Text('Scan receipt', style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Use OCR to prefill an expense'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _scanReceipt();
                },
              ),
            ],
          ),
        ),
      ),
    );
    if (type != null && mounted) await _addTransaction(initialType: type);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      DashboardScreen(
        controller: widget.controller,
        onAdd: _addTransaction,
        onScan: _scanReceipt,
        onSeeAll: () => setState(() => _index = 1),
        onEdit: _editTransaction,
        onGoals: () => setState(() => _index = 3),
      ),
      TransactionsScreen(
        controller: widget.controller,
        onEdit: _editTransaction,
      ),
      ReportsScreen(controller: widget.controller),
      SavingsGoalsScreen(controller: widget.controller),
      SettingsScreen(controller: widget.controller),
    ];

    const titles = ['Overview', 'Activity', 'Reports', 'Savings goals', 'Settings'];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.controller.sharedBudgetActive ? widget.controller.sharedBudgetName : titles[_index]),
        actions: [
          if (widget.controller.sharedBudgetActive)
            IconButton(
              tooltip: widget.controller.sharedConflicts.isNotEmpty ? 'Resolve sync conflicts' : 'Shared budget sync',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SharedBudgetScreen(controller: widget.controller))),
              icon: Icon(widget.controller.sharedSyncError != null || widget.controller.sharedConflicts.isNotEmpty
                  ? Icons.sync_problem : widget.controller.sharedPendingCount > 0 ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined),
            ),
          if (_index == 0)
            IconButton.filledTonal(
              tooltip: 'Scan receipt',
              onPressed: _scanReceipt,
              icon: const Icon(Icons.document_scanner_rounded),
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: IndexedStack(key: ValueKey(widget.controller.sharedBudgetId), index: _index, children: pages),
      floatingActionButton: _index <= 1
          ? FloatingActionButton.extended(
              onPressed: _showAddMenu,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Activity',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights_rounded),
            label: 'Reports',
          ),
          NavigationDestination(
            icon: Icon(Icons.savings_outlined),
            selectedIcon: Icon(Icons.savings_rounded),
            label: 'Goals',
          ),
          NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
