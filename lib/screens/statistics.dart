import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';
import '../models/transaction.dart';
import '../utils/app_categories.dart';
import '../utils/formatters.dart';

class StatisticsScreen extends StatefulWidget {
  final AppController controller;

  const StatisticsScreen({super.key, required this.controller});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _moveMonth(int offset) {
    final next = DateTime(_month.year, _month.month + offset);
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    if (next.isAfter(currentMonth)) return;
    setState(() => _month = next);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        final items = controller.transactionsForMonth(_month);
        final expenses = items.where((item) => item.isExpense).toList();
        final incomes = items.where((item) => item.isIncome).toList();
        final spent = expenses.fold<double>(0, (sum, item) => sum + item.amount);
        final income = incomes.fold<double>(0, (sum, item) => sum + item.amount);
        final net = income - spent;
        final savingsRate = income <= 0 ? 0.0 : (net / income) * 100;
        final totals = _categoryTotals(expenses);
        final previous = DateTime(_month.year, _month.month - 1);
        final previousSpent = controller.spentForMonth(previous);
        final change = previousSpent <= 0 ? null : ((spent - previousSpent) / previousSpent) * 100;
        final biggest = expenses.isEmpty
            ? null
            : expenses.reduce((a, b) => a.amount >= b.amount ? a : b);
        final days = _daysForAverage(_month);
        final dailyAverage = days == 0 ? 0.0 : spent / days;
        final isCurrentMonth = _month.year == DateTime.now().year && _month.month == DateTime.now().month;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
          children: [
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Previous month',
                  onPressed: () => _moveMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    AppFormatters.month(_month),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Next month',
                  onPressed: isCurrentMonth ? null : () => _moveMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.55,
              children: [
                _StatCard(
                  label: 'Income',
                  value: AppFormatters.compactMoney(income, currencyCode: controller.currencyCode),
                  icon: Icons.trending_up_rounded,
                ),
                _StatCard(
                  label: 'Spent',
                  value: AppFormatters.compactMoney(spent, currencyCode: controller.currencyCode),
                  icon: Icons.payments_rounded,
                ),
                _StatCard(
                  label: net >= 0 ? 'Net saved' : 'Net outflow',
                  value: AppFormatters.compactMoney(net.abs(), currencyCode: controller.currencyCode),
                  icon: net >= 0 ? Icons.savings_rounded : Icons.trending_down_rounded,
                ),
                _StatCard(
                  label: 'Savings rate',
                  value: income <= 0 ? '—' : '${savingsRate.toStringAsFixed(0)}%',
                  icon: Icons.percent_rounded,
                ),
              ],
            ),
            const SizedBox(height: 22),
            _ReportSummaryCard(
              spent: spent,
              previousSpent: previousSpent,
              change: change,
              dailyAverage: dailyAverage,
              biggest: biggest,
              transactionCount: items.length,
              currencyCode: controller.currencyCode,
            ),
            const SizedBox(height: 28),
            Text(
              'Spending by category',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            if (totals.isEmpty)
              const _EmptyChart()
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 220,
                        child: PieChart(
                          PieChartData(
                            centerSpaceRadius: 58,
                            sectionsSpace: 3,
                            startDegreeOffset: -90,
                            sections: totals.entries.map((entry) {
                              final percentage = spent == 0 ? 0 : (entry.value / spent) * 100;
                              return PieChartSectionData(
                                value: entry.value,
                                color: AppCategories.colorFor(entry.key, Theme.of(context).colorScheme),
                                radius: 42,
                                showTitle: percentage >= 8,
                                title: '${percentage.round()}%',
                                titleStyle: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ...totals.entries.map(
                        (entry) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: _CategoryRow(
                            category: entry.key,
                            amount: entry.value,
                            total: spent,
                            currencyCode: controller.currencyCode,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 28),
            Text(
              'Category budget status',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _CategoryBudgetReport(controller: controller, month: _month),
            const SizedBox(height: 28),
            if (isCurrentMonth) ...[
              Text(
                'Budget pace',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              _BudgetPaceCard(
                budget: controller.monthlyBudget,
                spent: spent,
              ),
            ],
          ],
        );
      },
    );
  }

  Map<String, double> _categoryTotals(List<Transaction> items) {
    final totals = <String, double>{};
    for (final item in items) {
      totals[item.category] = (totals[item.category] ?? 0) + item.amount;
    }
    final sorted = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted);
  }

  int _daysForAverage(DateTime month) {
    final now = DateTime.now();
    if (month.year == now.year && month.month == now.month) return now.day;
    return DateTime(month.year, month.month + 1, 0).day;
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary, size: 22),
            const SizedBox(height: 12),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportSummaryCard extends StatelessWidget {
  final double spent;
  final double previousSpent;
  final double? change;
  final double dailyAverage;
  final Transaction? biggest;
  final int transactionCount;
  final String currencyCode;

  const _ReportSummaryCard({
    required this.spent,
    required this.previousSpent,
    required this.change,
    required this.dailyAverage,
    required this.biggest,
    required this.transactionCount,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final changeText = change == null
        ? 'No previous-month comparison yet.'
        : change!.abs() < 0.5
            ? 'Spending is about the same as last month.'
            : change! > 0
                ? 'Spending is ${change!.abs().toStringAsFixed(0)}% higher than last month.'
                : 'Spending is ${change!.abs().toStringAsFixed(0)}% lower than last month.';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Monthly report', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 14),
            _SummaryLine(icon: Icons.compare_arrows_rounded, text: changeText),
            const SizedBox(height: 10),
            _SummaryLine(
              icon: Icons.today_rounded,
              text: 'Average daily spending: ${AppFormatters.money(dailyAverage, currencyCode: currencyCode)}.',
            ),
            const SizedBox(height: 10),
            _SummaryLine(
              icon: Icons.receipt_long_rounded,
              text: '$transactionCount total ${transactionCount == 1 ? 'transaction' : 'transactions'} this month.',
            ),
            if (biggest != null) ...[
              const SizedBox(height: 10),
              _SummaryLine(
                icon: Icons.arrow_circle_up_rounded,
                text: 'Largest expense: ${biggest!.store} at ${AppFormatters.money(biggest!.amount, currencyCode: currencyCode)}.',
              ),
            ],
            if (previousSpent == 0 && spent == 0) ...[
              const SizedBox(height: 12),
              Text('Add activity to unlock richer monthly comparisons.', style: TextStyle(color: scheme.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SummaryLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(height: 1.4))),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final String category;
  final double amount;
  final double total;
  final String currencyCode;

  const _CategoryRow({
    required this.category,
    required this.amount,
    required this.total,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = AppCategories.colorFor(category, scheme);
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(child: Text(category, style: const TextStyle(fontWeight: FontWeight.w700))),
        Text('${((amount / total) * 100).round()}%', style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(width: 14),
        Text(AppFormatters.money(amount, currencyCode: currencyCode), style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _CategoryBudgetReport extends StatelessWidget {
  final AppController controller;
  final DateTime month;

  const _CategoryBudgetReport({required this.controller, required this.month});

  @override
  Widget build(BuildContext context) {
    final categories = controller.categories
        .where((item) => item.type == TransactionType.expense && (item.monthlyBudget ?? 0) > 0)
        .toList();
    if (categories.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            'Set optional category budgets in Settings → Categories & budgets to track limits here.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: categories.map((category) {
            final spent = controller.categorySpent(category.name, month);
            final limit = category.monthlyBudget!;
            final raw = spent / limit;
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(category.name, style: const TextStyle(fontWeight: FontWeight.w800))),
                      Text('${(raw * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w900)),
                    ],
                  ),
                  const SizedBox(height: 7),
                  LinearProgressIndicator(value: raw.clamp(0.0, 1.0).toDouble(), minHeight: 7, borderRadius: BorderRadius.circular(99)),
                  const SizedBox(height: 5),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${AppFormatters.money(spent, currencyCode: controller.currencyCode)} / ${AppFormatters.money(limit, currencyCode: controller.currencyCode)}',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _BudgetPaceCard extends StatelessWidget {
  final double budget;
  final double spent;

  const _BudgetPaceCard({required this.budget, required this.spent});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final monthProgress = now.day / daysInMonth;
    final spendingProgress = budget <= 0 ? 0.0 : spent / budget;
    final onTrack = spendingProgress <= monthProgress + 0.08;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: onTrack ? scheme.primaryContainer : scheme.errorContainer,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                onTrack ? Icons.trending_flat_rounded : Icons.trending_up_rounded,
                color: onTrack ? scheme.onPrimaryContainer : scheme.onErrorContainer,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    onTrack ? 'You’re on a healthy pace' : 'Spending is running ahead',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${(monthProgress * 100).round()}% of the month has passed and you’ve used ${(spendingProgress * 100).round()}% of your budget.',
                    style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
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

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 22),
        child: Column(
          children: [
            Icon(Icons.pie_chart_outline_rounded, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            const Text('Reports appear as you spend', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'Add a few expenses to see your category breakdown.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
