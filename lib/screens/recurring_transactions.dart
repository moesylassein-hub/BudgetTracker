import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controllers/app_controller.dart';
import '../models/recurring_transaction.dart';
import '../models/transaction.dart';
import '../utils/formatters.dart';

class RecurringTransactionsScreen extends StatelessWidget {
  final AppController controller;

  const RecurringTransactionsScreen({
    super.key,
    required this.controller,
  });

  Future<void> _openEditor(
    BuildContext context, {
    RecurringTransaction? recurring,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _RecurringTransactionEditor(
          controller: controller,
          recurring: recurring,
        ),
      ),
    );
  }

  Future<void> _delete(
    BuildContext context,
    RecurringTransaction recurring,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete recurring transaction?'),
        content: Text(
          'This stops future ${recurring.title} entries. '
          'Transactions already created will stay in Activity.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await controller.deleteRecurringTransaction(recurring.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final rules = [...controller.recurringTransactions]
          ..sort((a, b) {
            if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
            final aNext = a.nextDueDate(DateTime.now());
            final bNext = b.nextDueDate(DateTime.now());
            if (aNext == null && bNext == null) {
              return a.title.compareTo(b.title);
            }
            if (aNext == null) return 1;
            if (bNext == null) return -1;
            return aNext.compareTo(bNext);
          });

        return Scaffold(
          appBar: AppBar(
            title: const Text('Recurring transactions'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
            children: [
              _IntroCard(controller: controller),
              const SizedBox(height: 18),
              if (rules.isEmpty)
                _EmptyState(onAdd: () => _openEditor(context))
              else ...[
                Text(
                  'YOUR RECURRING MONEY',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 9),
                for (final rule in rules) ...[
                  _RecurringCard(
                    controller: controller,
                    recurring: rule,
                    onEdit: () => _openEditor(
                      context,
                      recurring: rule,
                    ),
                    onToggle: () => controller.setRecurringTransactionActive(
                      rule.id,
                      !rule.isActive,
                    ),
                    onDelete: () => _delete(context, rule),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openEditor(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add recurring'),
          ),
        );
      },
    );
  }
}

class _IntroCard extends StatelessWidget {
  final AppController controller;

  const _IntroCard({required this.controller});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.repeat_rounded,
            color: scheme.onPrimaryContainer,
            size: 28,
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Automate salary, allowance and regular bills',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Due entries are created automatically when the app opens. '
                  'If you miss a due date, Budget Tracker safely catches it up once.',
                  style: TextStyle(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.82),
                    height: 1.4,
                  ),
                ),
                if (controller.activeRecurringCount > 0) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${controller.activeRecurringCount} active',
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 34,
        ),
        child: Column(
          children: [
            Icon(
              Icons.event_repeat_rounded,
              size: 50,
              color: scheme.primary,
            ),
            const SizedBox(height: 12),
            const Text(
              'No recurring transactions yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add your salary, allowance, rent, subscriptions or any regular payment.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add first recurring transaction'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecurringCard extends StatelessWidget {
  final AppController controller;
  final RecurringTransaction recurring;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _RecurringCard({
    required this.controller,
    required this.recurring,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final positive = recurring.isIncome;
    final amountColor = positive ? scheme.primary : scheme.error;
    final next = recurring.nextDueDate(DateTime.now());

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: amountColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  positive
                      ? Icons.south_west_rounded
                      : Icons.north_east_rounded,
                  color: amountColor,
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            recurring.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (!recurring.isActive) ...[
                          const SizedBox(width: 8),
                          _StatusChip(
                            label: 'Paused',
                            color: scheme.outline,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      AppFormatters.money(
                        recurring.amount,
                        currencyCode: controller.currencyCode,
                      ),
                      style: TextStyle(
                        color: amountColor,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _scheduleLabel(recurring),
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      !recurring.isActive
                          ? 'Paused — no future entries will be created'
                          : next == null
                              ? 'Schedule ended'
                              : 'Next: ${AppFormatters.date(next)}',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  switch (value) {
                    case 'edit':
                      onEdit();
                      break;
                    case 'toggle':
                      onToggle();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.edit_outlined),
                      title: Text('Edit'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'toggle',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        recurring.isActive
                            ? Icons.pause_circle_outline_rounded
                            : Icons.play_circle_outline_rounded,
                      ),
                      title: Text(
                        recurring.isActive ? 'Pause' : 'Resume',
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.delete_outline_rounded,
                        color: scheme.error,
                      ),
                      title: Text(
                        'Delete',
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _scheduleLabel(RecurringTransaction recurring) {
    if (recurring.frequency == RecurringFrequency.monthly) {
      return 'Monthly • Day ${recurring.dayOfMonth} • ${recurring.category}';
    }
    return 'Weekly • ${_weekdayName(recurring.weekday)} • ${recurring.category}';
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _RecurringTransactionEditor extends StatefulWidget {
  final AppController controller;
  final RecurringTransaction? recurring;

  const _RecurringTransactionEditor({
    required this.controller,
    this.recurring,
  });

  @override
  State<_RecurringTransactionEditor> createState() =>
      _RecurringTransactionEditorState();
}

class _RecurringTransactionEditorState
    extends State<_RecurringTransactionEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;

  late TransactionType _type;
  late RecurringFrequency _frequency;
  late String _category;
  late DateTime _startDate;
  DateTime? _endDate;
  late int _dayOfMonth;
  late int _weekday;
  late bool _isActive;
  bool _syncBudgetCycle = false;
  bool _saving = false;

  AppController get controller => widget.controller;
  RecurringTransaction? get existing => widget.recurring;

  @override
  void initState() {
    super.initState();
    final recurring = existing;
    _type = recurring?.type ?? TransactionType.income;
    _frequency = recurring?.frequency ?? RecurringFrequency.monthly;
    _startDate = recurring?.startDate ?? _today();
    _endDate = recurring?.endDate;
    _dayOfMonth = recurring?.dayOfMonth ?? _startDate.day;
    _weekday = recurring?.weekday ?? _startDate.weekday;
    _isActive = recurring?.isActive ?? true;
    _category = recurring?.category ?? controller.fallbackCategory(_type);
    _titleController = TextEditingController(
      text: recurring?.title ?? (_type == TransactionType.income ? 'Salary' : ''),
    );
    _amountController = TextEditingController(
      text: recurring == null ? '' : recurring.amount.toStringAsFixed(2),
    );
    _noteController = TextEditingController(text: recurring?.note ?? '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _changeType(TransactionType type) {
    if (_type == type) return;
    setState(() {
      _type = type;
      final available = controller.categoriesForType(type);
      if (!available.any((item) => item.name == _category)) {
        _category = controller.fallbackCategory(type);
      }
      if (existing == null &&
          _titleController.text.trim() == 'Salary' &&
          type == TransactionType.expense) {
        _titleController.clear();
      }
      if (type == TransactionType.expense) {
        _syncBudgetCycle = false;
      }
    });
  }

  Future<void> _pickStartDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected == null) return;
    setState(() {
      _startDate = selected;
      if (_frequency == RecurringFrequency.weekly) {
        _weekday = selected.weekday;
      }
    });
  }

  Future<void> _pickEndDate() async {
    final initial = _endDate ??
        DateTime(
          _startDate.year + 1,
          _startDate.month,
          _startDate.day,
        );
    final selected = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(_startDate) ? _startDate : initial,
      firstDate: _startDate,
      lastDate: DateTime(2100),
    );
    if (selected != null) {
      setState(() => _endDate = selected);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    final amount = double.parse(_amountController.text.trim());
    if (_endDate != null && _endDate!.isBefore(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End date must be after the start date.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final recurring = RecurringTransaction(
        id: existing?.id ?? now.microsecondsSinceEpoch.toString(),
        title: _titleController.text.trim(),
        amount: amount,
        category: _category,
        type: _type,
        frequency: _frequency,
        startDate: _startDate,
        endDate: _endDate,
        dayOfMonth: _dayOfMonth,
        weekday: _weekday,
        note: _noteController.text.trim(),
        isActive: _isActive,
        lastGeneratedOn: existing?.lastGeneratedOn,
        createdAt: existing?.createdAt ?? now,
      );

      if (existing == null) {
        await controller.addRecurringTransaction(recurring);
      } else {
        await controller.updateRecurringTransaction(recurring);
      }

      if (_syncBudgetCycle &&
          _type == TransactionType.income &&
          _frequency == RecurringFrequency.monthly) {
        await controller.setBudgetCycleStartDay(_dayOfMonth);
      }

      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = controller.categoriesForType(_type);
    if (!categories.any((item) => item.name == _category) &&
        categories.isNotEmpty) {
      _category = categories.first.name;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(existing == null ? 'Add recurring' : 'Edit recurring'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            Text(
              'TYPE',
              style: _sectionStyle(context),
            ),
            const SizedBox(height: 8),
            SegmentedButton<TransactionType>(
              segments: const [
                ButtonSegment(
                  value: TransactionType.income,
                  icon: Icon(Icons.add_circle_outline_rounded),
                  label: Text('Income'),
                ),
                ButtonSegment(
                  value: TransactionType.expense,
                  icon: Icon(Icons.remove_circle_outline_rounded),
                  label: Text('Expense'),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (value) => _changeType(value.first),
            ),
            const SizedBox(height: 22),
            Text(
              'DETAILS',
              style: _sectionStyle(context),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _titleController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: _type == TransactionType.income
                    ? 'Name'
                    : 'Merchant / bill',
                hintText: _type == TransactionType.income
                    ? 'Salary or allowance'
                    : 'Rent, Netflix, internet...',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a name'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount',
                suffixText: controller.currencyCode,
              ),
              validator: (value) {
                final parsed = double.tryParse(value?.trim() ?? '');
                return parsed == null || parsed <= 0
                    ? 'Enter an amount greater than 0'
                    : null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: categories
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.name,
                      child: Text(item.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _category = value);
              },
            ),
            const SizedBox(height: 22),
            Text(
              'SCHEDULE',
              style: _sectionStyle(context),
            ),
            const SizedBox(height: 8),
            SegmentedButton<RecurringFrequency>(
              segments: const [
                ButtonSegment(
                  value: RecurringFrequency.monthly,
                  icon: Icon(Icons.calendar_month_rounded),
                  label: Text('Monthly'),
                ),
                ButtonSegment(
                  value: RecurringFrequency.weekly,
                  icon: Icon(Icons.date_range_rounded),
                  label: Text('Weekly'),
                ),
              ],
              selected: {_frequency},
              onSelectionChanged: (value) {
                setState(() {
                  _frequency = value.first;
                  if (_frequency == RecurringFrequency.weekly) {
                    _weekday = _startDate.weekday;
                    _syncBudgetCycle = false;
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            if (_frequency == RecurringFrequency.monthly)
              DropdownButtonFormField<int>(
                initialValue: _dayOfMonth,
                decoration: const InputDecoration(
                  labelText: 'Payment day',
                  helperText:
                      'Days 29–31 automatically use the last valid day in shorter months.',
                ),
                items: [
                  for (var day = 1; day <= 31; day++)
                    DropdownMenuItem(
                      value: day,
                      child: Text('Day $day'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _dayOfMonth = value);
                  }
                },
              )
            else
              DropdownButtonFormField<int>(
                initialValue: _weekday,
                decoration: const InputDecoration(labelText: 'Payment day'),
                items: [
                  for (var day = DateTime.monday;
                      day <= DateTime.sunday;
                      day++)
                    DropdownMenuItem(
                      value: day,
                      child: Text(_weekdayName(day)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _weekday = value);
                  }
                },
              ),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.play_arrow_rounded),
                    title: const Text(
                      'Start date',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(AppFormatters.date(_startDate)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _pickStartDate,
                  ),
                  const Divider(height: 1, indent: 56),
                  ListTile(
                    leading: const Icon(Icons.stop_circle_outlined),
                    title: const Text(
                      'End date',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      _endDate == null
                          ? 'No end date'
                          : AppFormatters.date(_endDate!),
                    ),
                    trailing: _endDate == null
                        ? const Icon(Icons.chevron_right_rounded)
                        : IconButton(
                            tooltip: 'Remove end date',
                            onPressed: () => setState(() => _endDate = null),
                            icon: const Icon(Icons.close_rounded),
                          ),
                    onTap: _pickEndDate,
                  ),
                ],
              ),
            ),
            if (_type == TransactionType.income &&
                _frequency == RecurringFrequency.monthly) ...[
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                title: const Text(
                  'Start my budget cycle on this day',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  'Set the budget cycle to Day $_dayOfMonth so reports follow this income date.',
                ),
                value: _syncBudgetCycle,
                onChanged: (value) {
                  setState(() => _syncBudgetCycle = value);
                },
              ),
            ],
            const SizedBox(height: 22),
            Text(
              'OPTIONS',
              style: _sectionStyle(context),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _noteController,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'e.g. Main job salary',
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text(
                'Active',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Paused rules stay saved but do not create transactions.',
              ),
              value: _isActive,
              onChanged: (value) => setState(() => _isActive = value),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded),
          label: Text(existing == null ? 'Create recurring' : 'Save changes'),
        ),
      ),
    );
  }

  TextStyle _sectionStyle(BuildContext context) => TextStyle(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        fontSize: 12,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
      );

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
}

String _weekdayName(int weekday) {
  final date = DateTime(2026, 1, 5 + (weekday - DateTime.monday));
  return DateFormat('EEEE').format(date);
}
