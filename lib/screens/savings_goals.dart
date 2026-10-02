import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/savings_goal.dart';
import '../utils/app_categories.dart';
import '../utils/formatters.dart';

class SavingsGoalsScreen extends StatelessWidget {
  final AppController controller;

  const SavingsGoalsScreen({super.key, required this.controller});

  Future<void> _editGoal(BuildContext context, {SavingsGoal? goal}) async {
    final revision = goal == null ? null : controller.sharedRevision('goal:${goal.id}');
    var name = goal?.name ?? '';
    var targetText = goal?.targetAmount.toStringAsFixed(0) ?? '';
    var iconKey = goal?.iconKey ?? 'savings';
    final formKey = GlobalKey<FormState>();

    final result = await showModalBottomSheet<_GoalDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 24,
            ),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    goal == null ? 'New savings goal' : 'Edit savings goal',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 18),
                  TextFormField(
                    initialValue: name,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Goal name',
                      hintText: 'e.g. New laptop',
                      prefixIcon: Icon(Icons.flag_rounded),
                    ),
                    onChanged: (value) => name = value,
                    validator: (value) => value == null || value.trim().length < 2 ? 'Enter a goal name.' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: targetText,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Target amount',
                      suffixText: controller.currencyCode,
                      prefixIcon: const Icon(Icons.savings_rounded),
                    ),
                    onChanged: (value) => targetText = value,
                    validator: (value) {
                      final amount = double.tryParse(value?.trim() ?? '');
                      if (amount == null || amount <= 0) return 'Enter a valid target.';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: iconKey,
                    decoration: const InputDecoration(
                      labelText: 'Icon',
                      prefixIcon: Icon(Icons.emoji_symbols_rounded),
                    ),
                    items: AppCategories.iconOptions
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.key,
                            child: Row(
                              children: [
                                Icon(item.icon, size: 20),
                                const SizedBox(width: 10),
                                Text(item.label),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) setModalState(() => iconKey = value);
                    },
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        if (!(formKey.currentState?.validate() ?? false)) return;
                        Navigator.pop(
                          sheetContext,
                          _GoalDraft(
                            name: name.trim(),
                            targetAmount: double.parse(targetText.trim()),
                            iconKey: iconKey,
                          ),
                        );
                      },
                      child: Text(goal == null ? 'Create goal' : 'Save changes'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (result == null) return;
    if (goal == null) {
      await controller.addGoal(
        SavingsGoal(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: result.name,
          targetAmount: result.targetAmount,
          savedAmount: 0,
          iconKey: result.iconKey,
          createdAt: DateTime.now(),
        ),
      );
    } else {
      await controller.updateGoal(
        goal.copyWith(
          name: result.name,
          targetAmount: result.targetAmount,
          iconKey: result.iconKey,
        ),
        revision: revision,
      );
    }
  }

  Future<void> _adjustSavings(BuildContext context, SavingsGoal goal) async {
    var amountText = '';
    var add = true;
    final formKey = GlobalKey<FormState>();
    final result = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Update ${goal.name}'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('Add'), icon: Icon(Icons.add_rounded)),
                    ButtonSegment(value: false, label: Text('Withdraw'), icon: Icon(Icons.remove_rounded)),
                  ],
                  selected: {add},
                  onSelectionChanged: (selection) => setDialogState(() => add = selection.first),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Amount',
                    suffixText: controller.currencyCode,
                  ),
                  onChanged: (value) => amountText = value,
                  validator: (value) {
                    final amount = double.tryParse(value?.trim() ?? '');
                    if (amount == null || amount <= 0) return 'Enter a valid amount.';
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (!(formKey.currentState?.validate() ?? false)) return;
                final amount = double.parse(amountText.trim());
                Navigator.pop(dialogContext, add ? amount : -amount);
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
    if (result != null) await controller.changeGoalSavings(goal.id, result);
  }

  Future<void> _deleteGoal(BuildContext context, SavingsGoal goal) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete savings goal?'),
        content: Text('Remove “${goal.name}”? This does not delete any transactions.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) await controller.deleteGoal(goal.id);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final goals = controller.goals;
        final totalSaved = goals.fold<double>(0, (sum, item) => sum + item.savedAmount);
        final totalTarget = goals.fold<double>(0, (sum, item) => sum + item.targetAmount);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(Icons.savings_rounded, color: Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppFormatters.money(totalSaved, currencyCode: controller.currencyCode),
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 21),
                          ),
                          Text(
                            goals.isEmpty
                                ? 'Create a goal and start tracking progress.'
                                : 'saved across ${goals.length} ${goals.length == 1 ? 'goal' : 'goals'} • target ${AppFormatters.money(totalTarget, currencyCode: controller.currencyCode)}',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () => _editGoal(context),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New savings goal'),
            ),
            const SizedBox(height: 22),
            if (goals.isEmpty)
              const _EmptyGoals()
            else
              ...goals.map(
                (goal) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _GoalCard(
                    goal: goal,
                    currencyCode: controller.currencyCode,
                    onAdjust: () => _adjustSavings(context, goal),
                    onEdit: () => _editGoal(context, goal: goal),
                    onDelete: () => _deleteGoal(context, goal),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _GoalDraft {
  final String name;
  final double targetAmount;
  final String iconKey;

  const _GoalDraft({required this.name, required this.targetAmount, required this.iconKey});
}

class _GoalCard extends StatelessWidget {
  final SavingsGoal goal;
  final String currencyCode;
  final VoidCallback onAdjust;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _GoalCard({
    required this.goal,
    required this.currencyCode,
    required this.onAdjust,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(AppCategories.iconForKey(goal.iconKey), color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(goal.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                      const SizedBox(height: 2),
                      Text(
                        goal.completed ? 'Goal reached 🎉' : '${AppFormatters.money(goal.remaining, currencyCode: currencyCode)} remaining',
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'edit') onEdit();
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit goal')),
                    PopupMenuItem(value: 'delete', child: Text('Delete goal')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(value: goal.progress, minHeight: 10),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${AppFormatters.money(goal.savedAmount, currencyCode: currencyCode)} / ${AppFormatters.money(goal.targetAmount, currencyCode: currencyCode)}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                Text('${(goal.progress * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w900)),
              ],
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onAdjust,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('Update savings'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyGoals extends StatelessWidget {
  const _EmptyGoals();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 42),
      child: Column(
        children: [
          Icon(Icons.flag_circle_outlined, size: 58, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 14),
          const Text('Turn plans into progress', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 6),
          Text(
            'Create goals for a laptop, trip, emergency fund, car, or anything else you are saving toward.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
