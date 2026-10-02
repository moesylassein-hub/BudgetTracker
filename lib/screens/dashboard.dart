import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/receipt_scan_result.dart';
import '../models/transaction.dart';
import '../utils/formatters.dart';
import '../widgets/budget_card.dart';
import '../widgets/transaction_card.dart';

class DashboardScreen extends StatelessWidget {
  final AppController controller;
  final Future<void> Function({ReceiptScanResult? scan, TransactionType initialType}) onAdd;
  final Future<void> Function() onScan;
  final VoidCallback onSeeAll;
  final Future<void> Function(Transaction transaction) onEdit;
  final VoidCallback onGoals;

  const DashboardScreen({
    super.key,
    required this.controller,
    required this.onAdd,
    required this.onScan,
    required this.onSeeAll,
    required this.onEdit,
    required this.onGoals,
  });

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    final transactions = controller.currentMonthTransactions;
    final expenses = controller.currentMonthExpenses;
    final spent = controller.currentMonthSpent;
    final income = controller.currentMonthIncome;
    final net = controller.currentMonthNet;
    final budget = controller.monthlyBudget;
    final topCategory = _topCategory(expenses);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
      children: [
        Text(
          '${_greeting()} 👋',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 14),
        BudgetCard(
          budget: budget,
          spent: spent,
          currencyCode: controller.currencyCode,
          periodLabel: AppFormatters.dateRange(
            controller.currentCycleStart,
            controller.currentCycleEndExclusive.subtract(const Duration(days: 1)),
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.98,
          children: [
            _QuickAction(
              icon: Icons.remove_circle_outline_rounded,
              title: 'Expense',
              subtitle: 'Quick add',
              onTap: () => onAdd(initialType: TransactionType.expense),
            ),
            _QuickAction(
              icon: Icons.add_circle_outline_rounded,
              title: 'Income',
              subtitle: 'Add money in',
              onTap: () => onAdd(initialType: TransactionType.income),
            ),
            _QuickAction(
              icon: Icons.document_scanner_rounded,
              title: 'Scan',
              subtitle: 'Receipt OCR',
              onTap: onScan,
            ),
          ],
        ),
        const SizedBox(height: 24),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.65,
          children: [
            _MiniStat(
              label: 'Income',
              value: AppFormatters.compactMoney(income, currencyCode: controller.currencyCode),
              icon: Icons.trending_up_rounded,
            ),
            _MiniStat(
              label: net >= 0 ? 'Net saved' : 'Net outflow',
              value: AppFormatters.compactMoney(net.abs(), currencyCode: controller.currencyCode),
              icon: net >= 0 ? Icons.savings_outlined : Icons.trending_down_rounded,
            ),
            _MiniStat(
              label: 'Spent',
              value: AppFormatters.compactMoney(spent, currencyCode: controller.currencyCode),
              icon: Icons.payments_outlined,
            ),
            _MiniStat(
              label: 'Top category',
              value: topCategory,
              icon: Icons.category_outlined,
            ),
          ],
        ),
        if (controller.goals.isNotEmpty) ...[
          const SizedBox(height: 28),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Savings goals',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              TextButton(onPressed: onGoals, child: const Text('View goals')),
            ],
          ),
          const SizedBox(height: 8),
          _GoalPreview(
            name: controller.goals.first.name,
            saved: controller.goals.first.savedAmount,
            target: controller.goals.first.targetAmount,
            currencyCode: controller.currencyCode,
            onTap: onGoals,
          ),
        ],
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent activity',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            TextButton(onPressed: onSeeAll, child: const Text('See all')),
          ],
        ),
        const SizedBox(height: 8),
        if (transactions.isEmpty)
          const _EmptyRecent()
        else
          ...transactions.take(5).map(
                (transaction) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TransactionCard(
                    transaction: transaction,
                    authorship: controller.transactionAuthorship(transaction.id),
                    currencyCode: controller.currencyCode,
                    iconKey: controller.categoryByName(transaction.category)?.iconKey,
                    onTap: () => onEdit(transaction),
                  ),
                ),
              ),
      ],
    );
  }

  String _topCategory(List<Transaction> transactions) {
    if (transactions.isEmpty) return 'No data yet';
    final totals = <String, double>{};
    for (final item in transactions) {
      totals[item.category] = (totals[item.category] ?? 0) + item.amount;
    }
    final positive = totals.entries.where((entry) => entry.value > 0).toList();
    return positive.isEmpty ? 'No net spending' : positive.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: scheme.primary),
            const Spacer(),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MiniStat({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalPreview extends StatelessWidget {
  final String name;
  final double saved;
  final double target;
  final String currencyCode;
  final VoidCallback onTap;

  const _GoalPreview({
    required this.name,
    required this.saved,
    required this.target,
    required this.currencyCode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final progress = target <= 0 ? 0.0 : (saved / target).clamp(0.0, 1.0).toDouble();
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.savings_rounded),
                  const SizedBox(width: 10),
                  Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w900))),
                  Text('${(progress * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
              const SizedBox(height: 14),
              LinearProgressIndicator(value: progress, minHeight: 8, borderRadius: BorderRadius.circular(99)),
              const SizedBox(height: 9),
              Text(
                '${AppFormatters.money(saved, currencyCode: currencyCode)} of ${AppFormatters.money(target, currencyCode: currencyCode)}',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 34),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_rounded, size: 42, color: scheme.primary),
          const SizedBox(height: 12),
          const Text('Your money story starts here', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'Add an expense, income, or scan a receipt to see reports.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
