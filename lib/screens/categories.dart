import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/budget_category.dart';
import '../models/transaction.dart';
import '../utils/app_categories.dart';
import '../utils/formatters.dart';

class CategoriesScreen extends StatelessWidget {
  final AppController controller;

  const CategoriesScreen({super.key, required this.controller});

  Future<void> _editCategory(
    BuildContext context, {
    BudgetCategory? category,
    TransactionType initialType = TransactionType.expense,
  }) async {
    var name = category?.name ?? '';
    var iconKey = category?.iconKey ?? 'category';
    var type = category?.type ?? initialType;
    var budgetText = category?.monthlyBudget?.toStringAsFixed(0) ?? '';
    final formKey = GlobalKey<FormState>();

    final result = await showModalBottomSheet<_CategoryDraft>(
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
                    category == null ? 'New category' : 'Edit category',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 18),
                  if (category == null)
                    SegmentedButton<TransactionType>(
                      segments: const [
                        ButtonSegment(value: TransactionType.expense, label: Text('Expense')),
                        ButtonSegment(value: TransactionType.income, label: Text('Income')),
                      ],
                      selected: {type},
                      onSelectionChanged: (selection) => setModalState(() {
                        type = selection.first;
                        if (type == TransactionType.income) budgetText = '';
                      }),
                    )
                  else
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Category type'),
                      child: Text(type.label),
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: name,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Category name',
                      prefixIcon: Icon(Icons.label_rounded),
                    ),
                    onChanged: (value) => name = value,
                    validator: (value) {
                      final cleaned = value?.trim() ?? '';
                      if (cleaned.length < 2) return 'Enter a category name.';
                      final duplicate = controller.categories.any(
                        (item) => item.id != category?.id && item.name.toLowerCase() == cleaned.toLowerCase(),
                      );
                      if (duplicate) return 'That category already exists.';
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
                  if (type == TransactionType.expense) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: budgetText,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Monthly category budget (optional)',
                        hintText: 'No limit',
                        suffixText: controller.currencyCode,
                        prefixIcon: const Icon(Icons.speed_rounded),
                      ),
                      onChanged: (value) => budgetText = value,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) return null;
                        final amount = double.tryParse(value.trim());
                        if (amount == null || amount <= 0) return 'Enter a valid budget or leave it empty.';
                        return null;
                      },
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        if (!(formKey.currentState?.validate() ?? false)) return;
                        Navigator.pop(
                          sheetContext,
                          _CategoryDraft(
                            name: name.trim(),
                            iconKey: iconKey,
                            type: type,
                            budget: type == TransactionType.expense && budgetText.trim().isNotEmpty
                                ? double.parse(budgetText.trim())
                                : null,
                          ),
                        );
                      },
                      child: Text(category == null ? 'Create category' : 'Save category'),
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
    if (category == null) {
      await controller.addCategory(
        BudgetCategory(
          id: 'category-${DateTime.now().microsecondsSinceEpoch}',
          name: result.name,
          iconKey: result.iconKey,
          type: result.type,
          monthlyBudget: result.budget,
        ),
      );
    } else {
      await controller.updateCategory(
        BudgetCategory(
          id: category.id,
          name: result.name,
          iconKey: result.iconKey,
          type: result.type,
          monthlyBudget: result.budget,
        ),
      );
    }
  }

  Future<void> _deleteCategory(BuildContext context, BudgetCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text(
          'Delete “${category.name}”? Categories used by transactions or recurring rules cannot be deleted until those references are moved to another category.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    final deleted = await controller.deleteCategory(category.id);
    if (!context.mounted) return;
    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This category is used by a transaction or recurring rule, or it is the last category of its type, so it was kept.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Categories & budgets')),
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final expenses = controller.categoriesForType(TransactionType.expense);
          final income = controller.categoriesForType(TransactionType.income);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Text(
                'Expense categories',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'Optional category budgets power your category budget alerts.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              ...expenses.map(
                (category) => _CategoryTile(
                  category: category,
                  controller: controller,
                  onEdit: () => _editCategory(context, category: category),
                  onDelete: () => _deleteCategory(context, category),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _editCategory(context, initialType: TransactionType.expense),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add expense category'),
              ),
              const SizedBox(height: 28),
              Text(
                'Income categories',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              ...income.map(
                (category) => _CategoryTile(
                  category: category,
                  controller: controller,
                  onEdit: () => _editCategory(context, category: category),
                  onDelete: () => _deleteCategory(context, category),
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _editCategory(context, initialType: TransactionType.income),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add income category'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final BudgetCategory category;
  final AppController controller;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CategoryTile({
    required this.category,
    required this.controller,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final spent = category.type == TransactionType.expense
        ? controller.categorySpent(category.name, DateTime.now())
        : 0.0;
    final budget = category.monthlyBudget;
    final progress = budget == null || budget <= 0 ? null : (spent / budget).clamp(0.0, 1.0).toDouble();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(AppCategories.iconForKey(category.iconKey), color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(category.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                  if (category.type == TransactionType.expense) ...[
                    const SizedBox(height: 4),
                    Text(
                      budget == null
                          ? 'No category budget'
                          : '${AppFormatters.money(spent, currencyCode: controller.currencyCode)} / ${AppFormatters.money(budget, currencyCode: controller.currencyCode)} this month',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                    if (progress != null) ...[
                      const SizedBox(height: 7),
                      LinearProgressIndicator(value: progress, minHeight: 5, borderRadius: BorderRadius.circular(99)),
                    ],
                  ] else
                    Text('Income category', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') onEdit();
                if (value == 'delete') onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryDraft {
  final String name;
  final String iconKey;
  final TransactionType type;
  final double? budget;

  const _CategoryDraft({
    required this.name,
    required this.iconKey,
    required this.type,
    required this.budget,
  });
}
