import 'dart:async';

import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/transaction.dart';
import '../utils/formatters.dart';
import '../widgets/transaction_card.dart';

enum ActivityView { list, calendar }

class TransactionsScreen extends StatefulWidget {
  final AppController controller;
  final Future<void> Function(Transaction transaction) onEdit;

  const TransactionsScreen({
    super.key,
    required this.controller,
    required this.onEdit,
  });

  @override
  State<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends State<TransactionsScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  String _category = 'All';
  String _type = 'All';
  ActivityView _view = ActivityView.list;
  DateTime _selectedDate = DateTime.now();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Transaction> _filtered() {
    return widget.controller.transactions.where((item) {
      final query = _query.toLowerCase();
      final matchesQuery = query.isEmpty ||
          item.store.toLowerCase().contains(query) ||
          item.note.toLowerCase().contains(query) ||
          item.category.toLowerCase().contains(query);
      final matchesCategory = _category == 'All' || item.category == _category;
      final matchesType = _type == 'All' ||
          (_type == 'Expense' && item.isExpense) ||
          (_type == 'Income' && item.isIncome);
      return matchesQuery && matchesCategory && matchesType;
    }).toList();
  }

  List<Transaction> _selectedDayItems() {
    return widget.controller.transactionsForDay(_selectedDate);
  }

  Future<bool> _confirmDelete(Transaction transaction) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete transaction?'),
        content: Text('Remove “${transaction.store}” from your history?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    return answer ?? false;
  }

  Future<void> _deleteWithUndo(Transaction transaction) async {
    try {
      await widget.controller.deleteTransaction(transaction.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete this transaction. Please try again.')),
      );
      return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('${transaction.type.label} deleted.'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () {
            unawaited(widget.controller.addTransaction(transaction));
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
          children: [
            SegmentedButton<ActivityView>(
              segments: const [
                ButtonSegment(value: ActivityView.list, icon: Icon(Icons.view_list_rounded), label: Text('List')),
                ButtonSegment(value: ActivityView.calendar, icon: Icon(Icons.calendar_month_rounded), label: Text('Calendar')),
              ],
              selected: {_view},
              onSelectionChanged: (selection) => setState(() => _view = selection.first),
            ),
            const SizedBox(height: 16),
            if (_view == ActivityView.list) _buildListView(context) else _buildCalendarView(context),
          ],
        );
      },
    );
  }

  Widget _buildListView(BuildContext context) {
    final items = _filtered();
    final categories = widget.controller.categories.map((item) => item.name).toSet().toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _searchController,
          onChanged: (value) => setState(() => _query = value.trim()),
          decoration: InputDecoration(
            hintText: 'Search activity',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _query = '');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: ['All', 'Expense', 'Income']
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(item),
                      selected: _type == item,
                      onSelected: (_) => setState(() => _type = item),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: ['All', ...categories]
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(item),
                      selected: _category == item,
                      onSelected: (_) => setState(() => _category = item),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '${items.length} ${items.length == 1 ? 'transaction' : 'transactions'}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (_category != 'All' || _query.isNotEmpty || _type != 'All')
              TextButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _query = '';
                    _category = 'All';
                    _type = 'All';
                  });
                },
                child: const Text('Reset'),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          const _NoResults()
        else
          ...items.map(
            (transaction) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Dismissible(
                key: ValueKey(transaction.id),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) => _confirmDelete(transaction),
                onDismissed: (_) => unawaited(_deleteWithUndo(transaction)),
                background: Container(
                  padding: const EdgeInsets.only(right: 22),
                  alignment: Alignment.centerRight,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                child: TransactionCard(
                  transaction: transaction,
                  currencyCode: widget.controller.currencyCode,
                  iconKey: widget.controller.categoryByName(transaction.category)?.iconKey,
                  onTap: () => widget.onEdit(transaction),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCalendarView(BuildContext context) {
    final items = _selectedDayItems();
    final spent = items.where((item) => item.isExpense).fold<double>(0, (sum, item) => sum + item.amount);
    final income = items.where((item) => item.isIncome).fold<double>(0, (sum, item) => sum + item.amount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: CalendarDatePicker(
            initialDate: _selectedDate,
            firstDate: DateTime(2000),
            lastDate: DateTime.now().add(const Duration(days: 365)),
            onDateChanged: (value) => setState(() => _selectedDate = value),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          AppFormatters.weekday(_selectedDate),
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _DayStat(
                label: 'Income',
                value: AppFormatters.money(income, currencyCode: widget.controller.currencyCode),
                icon: Icons.trending_up_rounded,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _DayStat(
                label: 'Spent',
                value: AppFormatters.money(spent, currencyCode: widget.controller.currencyCode),
                icon: Icons.payments_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (items.isEmpty)
          const _NoDayActivity()
        else
          ...items.map(
            (transaction) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TransactionCard(
                transaction: transaction,
                currencyCode: widget.controller.currencyCode,
                iconKey: widget.controller.categoryByName(transaction.category)?.iconKey,
                onTap: () => widget.onEdit(transaction),
              ),
            ),
          ),
      ],
    );
  }
}

class _DayStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _DayStat({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w900)),
                  Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const _NoResults();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 54),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 52, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 14),
          const Text('Nothing found', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          const SizedBox(height: 6),
          Text('Try a different search, type, or category.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _NoDayActivity extends StatelessWidget {
  const _NoDayActivity();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34),
      child: Column(
        children: [
          Icon(Icons.event_available_rounded, size: 50, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          const Text('No activity on this day', style: TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
