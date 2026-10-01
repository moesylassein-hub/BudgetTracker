// ignore_for_file: prefer_interpolation_to_compose_strings

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controllers/app_controller.dart';
import '../models/transaction.dart';
import '../utils/app_categories.dart';
import '../utils/formatters.dart';

enum ReportSection { overview, trends, categories }

class ReportsScreen extends StatefulWidget {
  final AppController controller;

  const ReportsScreen({super.key, required this.controller});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late DateTime _cycle;
  late int _cycleStartDay;
  ReportSection _section = ReportSection.overview;

  @override
  void initState() {
    super.initState();
    _cycleStartDay = widget.controller.budgetCycleStartDay;
    _cycle = widget.controller.currentCycleStart;
  }

  void _moveCycle(int offset) {
    final controller = widget.controller;
    final anchor = DateTime(_cycle.year, _cycle.month + offset + 1, 0);
    final next = controller.budgetCycleStartFor(anchor);
    if (next.isAfter(controller.currentCycleStart)) return;
    setState(() => _cycle = next);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        if (_cycleStartDay != controller.budgetCycleStartDay) {
          _cycleStartDay = controller.budgetCycleStartDay;
          _cycle = controller.currentCycleStart;
        }

        final snapshot = _snapshot(controller, _cycle);
        final previous = _snapshot(
          controller,
          _cycleAtOffset(controller, _cycle, -1),
        );
        final history = [
          for (var offset = -5; offset <= 0; offset++)
            _snapshot(
              controller,
              _cycleAtOffset(controller, _cycle, offset),
            ),
        ];
        final previousThree = [
          for (var offset = -3; offset <= -1; offset++)
            _snapshot(
              controller,
              _cycleAtOffset(controller, _cycle, offset),
            ),
        ];
        final isCurrent = _sameDay(_cycle, controller.currentCycleStart);
        final analysis = _ReportAnalysis(
          controller: controller,
          snapshot: snapshot,
          previous: previous,
          previousThree: previousThree,
          isCurrent: isCurrent,
        );

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
          children: [
            _CycleHeader(
              controller: controller,
              cycle: _cycle,
              isCurrent: isCurrent,
              onPrevious: () => _moveCycle(-1),
              onNext: isCurrent ? null : () => _moveCycle(1),
              onCurrent: isCurrent
                  ? null
                  : () => setState(() => _cycle = controller.currentCycleStart),
            ),
            const SizedBox(height: 14),
            SegmentedButton<ReportSection>(
              segments: const [
                ButtonSegment(
                  value: ReportSection.overview,
                  icon: Icon(Icons.space_dashboard_rounded),
                  label: Text('Insights'),
                ),
                ButtonSegment(
                  value: ReportSection.trends,
                  icon: Icon(Icons.show_chart_rounded),
                  label: Text('Trends'),
                ),
                ButtonSegment(
                  value: ReportSection.categories,
                  icon: Icon(Icons.donut_large_rounded),
                  label: Text('Categories'),
                ),
              ],
              selected: {_section},
              onSelectionChanged: (value) {
                setState(() => _section = value.first);
              },
            ),
            const SizedBox(height: 18),
            if (_section == ReportSection.overview)
              _OverviewReport(
                controller: controller,
                analysis: analysis,
              )
            else if (_section == ReportSection.trends)
              _TrendsReport(
                controller: controller,
                analysis: analysis,
                history: history,
              )
            else
              _CategoriesReport(
                controller: controller,
                analysis: analysis,
              ),
          ],
        );
      },
    );
  }

  _CycleSnapshot _snapshot(AppController controller, DateTime cycle) {
    final items = controller.transactionsForMonth(cycle);
    final expenses = items.where((item) => item.isExpense).toList();
    final income = items.where((item) => item.isIncome).toList();
    return _CycleSnapshot(
      start: controller.budgetCycleStartFor(cycle),
      endExclusive: controller.budgetCycleEndExclusiveFor(cycle),
      transactions: items,
      expenses: expenses,
      incomeTransactions: income,
      spent: expenses.fold<double>(0, (sum, item) => sum + item.amount),
      income: income.fold<double>(0, (sum, item) => sum + item.amount),
    );
  }

  DateTime _cycleAtOffset(
    AppController controller,
    DateTime cycle,
    int offset,
  ) {
    if (offset == 0) return controller.budgetCycleStartFor(cycle);
    final anchor = DateTime(cycle.year, cycle.month + offset + 1, 0);
    return controller.budgetCycleStartFor(anchor);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _OverviewReport extends StatelessWidget {
  final AppController controller;
  final _ReportAnalysis analysis;

  const _OverviewReport({
    required this.controller,
    required this.analysis,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          title: 'Smart insights',
          subtitle: 'What stands out in this budget cycle',
        ),
        const SizedBox(height: 10),
        _InsightsCard(
          insights: analysis.insights,
        ),
        const SizedBox(height: 22),
        _SectionTitle(
          title: 'Spending timeline',
          subtitle: 'Cumulative spending across this cycle',
        ),
        const SizedBox(height: 10),
        _SpendingTimelineCard(
          controller: controller,
          analysis: analysis,
        ),
        const SizedBox(height: 22),
        _SectionTitle(
          title: 'Cycle highlights',
          subtitle: 'Your most important activity',
        ),
        const SizedBox(height: 10),
        _HighlightsCard(
          controller: controller,
          analysis: analysis,
        ),
      ],
    );
  }
}

class _TrendsReport extends StatelessWidget {
  final AppController controller;
  final _ReportAnalysis analysis;
  final List<_CycleSnapshot> history;

  const _TrendsReport({
    required this.controller,
    required this.analysis,
    required this.history,
  });

  @override
  Widget build(BuildContext context) {
    final historyWithData = history.where((item) => item.transactions.isNotEmpty);
    final averageSpent = historyWithData.isEmpty
        ? 0.0
        : historyWithData.fold<double>(0, (sum, item) => sum + item.spent) /
            historyWithData.length;
    final averageIncome = historyWithData.isEmpty
        ? 0.0
        : historyWithData.fold<double>(0, (sum, item) => sum + item.income) /
            historyWithData.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          title: '6-cycle cash flow',
          subtitle: 'Income versus spending over time',
        ),
        const SizedBox(height: 10),
        _CashFlowChart(
          history: history,
          currencyCode: controller.currencyCode,
        ),
        const SizedBox(height: 14),
        _MetricGrid(
          items: [
            _Metric(
              '6-cycle avg spent',
              AppFormatters.compactMoney(
                averageSpent,
                currencyCode: controller.currencyCode,
              ),
              Icons.payments_outlined,
            ),
            _Metric(
              '6-cycle avg income',
              AppFormatters.compactMoney(
                averageIncome,
                currencyCode: controller.currencyCode,
              ),
              Icons.account_balance_wallet_outlined,
            ),
            _Metric(
              'Vs previous',
              analysis.previousChange == null
                  ? '—'
                  : _signedPercent(analysis.previousChange!),
              analysis.previousChange != null && analysis.previousChange! <= 0
                  ? Icons.trending_down_rounded
                  : Icons.trending_up_rounded,
            ),
            _Metric(
              'Vs 3-cycle avg',
              analysis.threeCycleChange == null
                  ? '—'
                  : _signedPercent(analysis.threeCycleChange!),
              analysis.threeCycleChange != null &&
                      analysis.threeCycleChange! <= 0
                  ? Icons.trending_down_rounded
                  : Icons.trending_up_rounded,
            ),
          ],
        ),
        const SizedBox(height: 22),
        _SectionTitle(
          title: 'Cycle performance',
          subtitle: 'How this cycle compares with your recent pattern',
        ),
        const SizedBox(height: 10),
        _PerformanceCard(
          controller: controller,
          analysis: analysis,
        ),
      ],
    );
  }

  static String _signedPercent(double value) {
    final prefix = value > 0 ? '+' : '';
    return prefix + value.toStringAsFixed(0) + '%';
  }
}


class _CategoriesReport extends StatelessWidget {
  final AppController controller;
  final _ReportAnalysis analysis;

  const _CategoriesReport({
    required this.controller,
    required this.analysis,
  });

  @override
  Widget build(BuildContext context) {
    final totals = analysis.categoryTotals;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(
          title: 'Spending breakdown',
          subtitle: 'See which categories take the biggest share of this cycle',
        ),
        const SizedBox(height: 10),
        if (totals.isEmpty)
          const _EmptyReportCard(
            icon: Icons.donut_large_rounded,
            title: 'No category data yet',
            text: 'Add expenses to unlock your spending breakdown.',
          )
        else
          _EnhancedCategoryDonutCard(
            controller: controller,
            analysis: analysis,
          ),
        const SizedBox(height: 22),
        _SectionTitle(
          title: 'Category limits',
          subtitle: 'Which budgets are safe, close, or already exceeded',
        ),
        const SizedBox(height: 10),
        _CategoryBudgetCard(
          controller: controller,
          analysis: analysis,
        ),
      ],
    );
  }
}

class _EnhancedCategoryDonutCard extends StatefulWidget {
  final AppController controller;
  final _ReportAnalysis analysis;

  const _EnhancedCategoryDonutCard({
    required this.controller,
    required this.analysis,
  });

  @override
  State<_EnhancedCategoryDonutCard> createState() =>
      _EnhancedCategoryDonutCardState();
}

class _EnhancedCategoryDonutCardState
    extends State<_EnhancedCategoryDonutCard> {
  int _touchedIndex = -1;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final analysis = widget.analysis;
    final scheme = Theme.of(context).colorScheme;
    final all = analysis.categoryTotals.entries.toList();

    final slices = <_CategorySlice>[
      for (final entry in all.take(5))
        _CategorySlice(entry.key, entry.value),
    ];

    final otherTotal = all
        .skip(5)
        .fold<double>(0, (sum, entry) => sum + entry.value);
    if (otherTotal > 0) {
      slices.add(_CategorySlice('Other', otherTotal));
    }

    final total = analysis.snapshot.spent;
    final selected =
        _touchedIndex >= 0 && _touchedIndex < slices.length
            ? slices[_touchedIndex]
            : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        child: Column(
          children: [
            SizedBox(
              height: 245,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      centerSpaceRadius: 62,
                      sectionsSpace: 3,
                      startDegreeOffset: -90,
                      pieTouchData: PieTouchData(
                        touchCallback: (event, response) {
                          setState(() {
                            if (!event.isInterestedForInteractions ||
                                response?.touchedSection == null) {
                              _touchedIndex = -1;
                            } else {
                              _touchedIndex = response!
                                  .touchedSection!
                                  .touchedSectionIndex;
                            }
                          });
                        },
                      ),
                      sections: [
                        for (var i = 0; i < slices.length; i++)
                          PieChartSectionData(
                            value: slices[i].amount,
                            color: slices[i].name == 'Other'
                                ? scheme.outline
                                : AppCategories.colorFor(
                                    slices[i].name,
                                    scheme,
                                  ),
                            radius: i == _touchedIndex ? 52 : 43,
                            title: _slicePercent(
                                      slices[i].amount,
                                      total,
                                    ) >=
                                    8
                                ? _slicePercent(
                                        slices[i].amount,
                                        total,
                                      ).round().toString() +
                                    '%'
                                : '',
                            titleStyle: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                      ],
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: Column(
                      key: ValueKey(selected?.name ?? 'total'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          selected?.name ?? 'Total spent',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppFormatters.compactMoney(
                            selected?.amount ?? total,
                            currencyCode: controller.currencyCode,
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          ),
                        ),
                        if (selected != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            _slicePercent(selected.amount, total)
                                    .toStringAsFixed(1) +
                                '% of expenses',
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap a slice to inspect it. Smaller categories are grouped into Other.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (var i = 0; i < slices.length; i++)
                  InkWell(
                    borderRadius: BorderRadius.circular(99),
                    onTap: () {
                      setState(() {
                        _touchedIndex = _touchedIndex == i ? -1 : i;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: i == _touchedIndex
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: slices[i].name == 'Other'
                                  ? scheme.outline
                                  : AppCategories.colorFor(
                                      slices[i].name,
                                      scheme,
                                    ),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            slices[i].name +
                                ' ' +
                                _slicePercent(
                                  slices[i].amount,
                                  total,
                                ).round().toString() +
                                '%',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  double _slicePercent(double amount, double total) {
    if (total <= 0) return 0;
    return amount / total * 100;
  }
}

class _CategoryBudgetCard extends StatelessWidget {
  final AppController controller;
  final _ReportAnalysis analysis;

  const _CategoryBudgetCard({
    required this.controller,
    required this.analysis,
  });

  @override
  Widget build(BuildContext context) {
    final categories = controller.categories
        .where(
          (item) =>
              item.type == TransactionType.expense &&
              (item.monthlyBudget ?? 0) > 0,
        )
        .toList();

    if (categories.isEmpty) {
      return const _EmptyReportCard(
        icon: Icons.account_balance_wallet_outlined,
        title: 'No category limits yet',
        text: 'Set category budgets in Settings to track limits here.',
      );
    }

    categories.sort((a, b) {
      final aRatio =
          controller.categorySpent(a.name, analysis.snapshot.start) /
              (a.monthlyBudget ?? 1);
      final bRatio =
          controller.categorySpent(b.name, analysis.snapshot.start) /
              (b.monthlyBudget ?? 1);
      return bRatio.compareTo(aRatio);
    });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (var i = 0; i < categories.length; i++) ...[
              Builder(
                builder: (context) {
                  final category = categories[i];
                  final limit = category.monthlyBudget!;
                  final spent = controller.categorySpent(
                    category.name,
                    analysis.snapshot.start,
                  );
                  final raw = limit <= 0 ? 0.0 : spent / limit;
                  final remaining = limit - spent;
                  final over = remaining < 0;
                  final close = !over && raw >= 0.8;
                  final scheme = Theme.of(context).colorScheme;

                  return Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Icon(
                                  AppCategories.iconFor(
                                    category.name,
                                    iconKey: category.iconKey,
                                  ),
                                  size: 19,
                                  color: over
                                      ? scheme.error
                                      : close
                                          ? scheme.tertiary
                                          : scheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    category.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            over
                                ? AppFormatters.compactMoney(
                                      remaining.abs(),
                                      currencyCode: controller.currencyCode,
                                    ) +
                                    ' over'
                                : AppFormatters.compactMoney(
                                      remaining,
                                      currencyCode: controller.currencyCode,
                                    ) +
                                    ' left',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: over
                                  ? scheme.error
                                  : close
                                      ? scheme.tertiary
                                      : scheme.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: raw.clamp(0.0, 1.0).toDouble(),
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(99),
                        color: over
                            ? scheme.error
                            : close
                                ? scheme.tertiary
                                : scheme.primary,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            AppFormatters.money(
                                  spent,
                                  currencyCode: controller.currencyCode,
                                ) +
                                ' of ' +
                                AppFormatters.money(
                                  limit,
                                  currencyCode: controller.currencyCode,
                                ),
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            (raw * 100).round().toString() + '%',
                            style: TextStyle(
                              color: over
                                  ? scheme.error
                                  : scheme.onSurfaceVariant,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              if (i != categories.length - 1)
                const Divider(height: 26),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategorySlice {
  final String name;
  final double amount;

  const _CategorySlice(this.name, this.amount);
}

class _CycleHeader extends StatelessWidget {
  final AppController controller;
  final DateTime cycle;
  final bool isCurrent;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onCurrent;

  const _CycleHeader({
    required this.controller,
    required this.cycle,
    required this.isCurrent,
    required this.onPrevious,
    required this.onNext,
    required this.onCurrent,
  });

  @override
  Widget build(BuildContext context) {
    final start = controller.budgetCycleStartFor(cycle);
    final end = controller
        .budgetCycleEndExclusiveFor(cycle)
        .subtract(const Duration(days: 1));

    return Column(
      children: [
        Row(
          children: [
            IconButton.filledTonal(
              tooltip: 'Previous budget cycle',
              onPressed: onPrevious,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                children: [
                  Text(
                    AppFormatters.dateRange(start, end),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isCurrent ? 'Current budget cycle' : 'Past budget cycle',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: 'Next budget cycle',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
        if (!isCurrent) ...[
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: onCurrent,
            icon: const Icon(Icons.today_rounded, size: 18),
            label: const Text('Jump to current cycle'),
          ),
        ],
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  final List<_Metric> items;

  const _MetricGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: items.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.75,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        final scheme = Theme.of(context).colorScheme;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    item.icon,
                    color: scheme.onPrimaryContainer,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
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
      },
    );
  }
}

class _InsightsCard extends StatelessWidget {
  final List<_Insight> insights;

  const _InsightsCard({required this.insights});

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) {
      return const _EmptyReportCard(
        icon: Icons.auto_awesome_outlined,
        title: 'Insights need more data',
        text: 'A few more transactions will make this section smarter.',
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            for (var i = 0; i < insights.length; i++) ...[
              _InsightTile(insight: insights[i]),
              if (i != insights.length - 1)
                const Divider(height: 1, indent: 64),
            ],
          ],
        ),
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  final _Insight insight;

  const _InsightTile({required this.insight});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (insight.tone) {
      _InsightTone.good => scheme.primary,
      _InsightTone.warning => scheme.error,
      _InsightTone.neutral => scheme.tertiary,
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(insight.icon, color: color, size: 20),
      ),
      title: Text(
        insight.title,
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      subtitle: Text(
        insight.body,
        style: const TextStyle(height: 1.35),
      ),
    );
  }
}

class _SpendingTimelineCard extends StatelessWidget {
  final AppController controller;
  final _ReportAnalysis analysis;

  const _SpendingTimelineCard({
    required this.controller,
    required this.analysis,
  });

  @override
  Widget build(BuildContext context) {
    if (analysis.snapshot.expenses.isEmpty) {
      return const _EmptyReportCard(
        icon: Icons.show_chart_rounded,
        title: 'Your timeline is empty',
        text: 'Expense activity will build a cumulative spending line here.',
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final spots = analysis.cumulativeSpending;
    final budget = controller.monthlyBudget;
    final maxSpend = spots.fold<double>(
      0,
      (max, spot) => math.max(max, spot.y).toDouble(),
    );
    final maxY = math.max(math.max(maxSpend, budget), 1.0).toDouble() * 1.15;
    final days = analysis.snapshot.totalDays;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 18, 14),
        child: Column(
          children: [
            SizedBox(
              height: 230,
              child: LineChart(
                LineChartData(
                  minX: 1,
                  maxX: math.max(days.toDouble(), 2.0).toDouble(),
                  minY: 0,
                  maxY: maxY,
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: maxY / 4,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: scheme.outlineVariant.withValues(alpha: 0.45),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(
                        y: budget,
                        color: scheme.error.withValues(alpha: 0.65),
                        strokeWidth: 1.5,
                        dashArray: [6, 5],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topRight,
                          style: TextStyle(
                            color: scheme.error,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                          labelResolver: (_) => 'Budget',
                        ),
                      ),
                    ],
                  ),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48,
                        interval: maxY / 4,
                        getTitlesWidget: (value, meta) => Text(
                          AppFormatters.compactMoney(
                            value,
                            currencyCode: controller.currencyCode,
                          ),
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: math.max(1, days ~/ 3).toDouble(),
                        getTitlesWidget: (value, meta) => Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'D' + value.round().toString(),
                            style: TextStyle(
                              color: scheme.onSurfaceVariant,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (items) => items
                          .map(
                            (item) => LineTooltipItem(
                              'Day ' +
                                  item.x.round().toString() +
                                  '\n' +
                                  AppFormatters.money(
                                    item.y,
                                    currencyCode: controller.currencyCode,
                                  ),
                              TextStyle(
                                color: scheme.onInverseSurface,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      curveSmoothness: 0.25,
                      barWidth: 3,
                      color: scheme.primary,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: scheme.primary.withValues(alpha: 0.10),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              analysis.isCurrent
                  ? 'Projection uses your average daily spending so far.'
                  : 'This shows the final cumulative spending path for the cycle.',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HighlightsCard extends StatelessWidget {
  final AppController controller;
  final _ReportAnalysis analysis;

  const _HighlightsCard({
    required this.controller,
    required this.analysis,
  });

  @override
  Widget build(BuildContext context) {
    if (analysis.snapshot.transactions.isEmpty) {
      return const _EmptyReportCard(
        icon: Icons.stars_outlined,
        title: 'No highlights yet',
        text: 'Cycle highlights appear after you add activity.',
      );
    }

    final biggest = analysis.biggestExpense;
    final rows = <_HighlightRow>[
      if (biggest != null)
        _HighlightRow(
          Icons.arrow_upward_rounded,
          'Largest expense',
          biggest.store,
          AppFormatters.money(
            biggest.amount,
            currencyCode: controller.currencyCode,
          ),
        ),
      if (analysis.biggestDay != null)
        _HighlightRow(
          Icons.event_rounded,
          'Biggest spending day',
          AppFormatters.date(analysis.biggestDay!.date),
          AppFormatters.money(
            analysis.biggestDay!.amount,
            currencyCode: controller.currencyCode,
          ),
        ),
    ];

    return Card(
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              leading: Icon(
                rows[i].icon,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: Text(
                rows[i].label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              subtitle: Text(rows[i].detail),
              trailing: Text(
                rows[i].value,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            if (i != rows.length - 1)
              const Divider(height: 1, indent: 56),
          ],
        ],
      ),
    );
  }
}

class _CashFlowChart extends StatelessWidget {
  final List<_CycleSnapshot> history;
  final String currencyCode;

  const _CashFlowChart({
    required this.history,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxValue = history.fold<double>(
      0,
      (max, item) => math.max(
        max,
        math.max(item.spent, item.income),
      ).toDouble(),
    );
    final maxY = math.max(maxValue, 1.0).toDouble() * 1.2;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 14, 14),
        child: Column(
          children: [
            SizedBox(
              height: 250,
              child: BarChart(
                BarChartData(
                  minY: 0,
                  maxY: maxY,
                  alignment: BarChartAlignment.spaceAround,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final label = rodIndex == 0 ? 'Income' : 'Spent';
                        return BarTooltipItem(
                          label +
                              '\n' +
                              AppFormatters.money(
                                rod.toY,
                                currencyCode: currencyCode,
                              ),
                          const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        );
                      },
                    ),
                  ),
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    horizontalInterval: maxY / 4,
                    getDrawingHorizontalLine: (value) => FlLine(
                      color: scheme.outlineVariant.withValues(alpha: 0.4),
                      strokeWidth: 1,
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48,
                        interval: maxY / 4,
                        getTitlesWidget: (value, meta) => Text(
                          AppFormatters.compactMoney(
                            value,
                            currencyCode: currencyCode,
                          ),
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.round();
                          if (index < 0 || index >= history.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              DateFormat('MMM').format(history[index].start),
                              style: TextStyle(
                                color: scheme.onSurfaceVariant,
                                fontSize: 10,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < history.length; i++)
                      BarChartGroupData(
                        x: i,
                        barsSpace: 3,
                        barRods: [
                          BarChartRodData(
                            toY: history[i].income,
                            width: 8,
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(5),
                          ),
                          BarChartRodData(
                            toY: history[i].spent,
                            width: 8,
                            color: scheme.tertiary,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendDot(color: scheme.primary, label: 'Income'),
                const SizedBox(width: 18),
                _LegendDot(color: scheme.tertiary, label: 'Spent'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PerformanceCard extends StatelessWidget {
  final AppController controller;
  final _ReportAnalysis analysis;

  const _PerformanceCard({
    required this.controller,
    required this.analysis,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final budget = controller.monthlyBudget;
    final spent = analysis.snapshot.spent;
    final utilization = budget <= 0 ? 0.0 : spent / budget;
    final remainingPerDay = analysis.remainingDailyAllowance;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            _PerformanceRow(
              label: 'Budget used',
              value: (utilization * 100).round().toString() + '%',
              progress: utilization.clamp(0.0, 1.0).toDouble(),
            ),
            const SizedBox(height: 18),
            _PerformanceRow(
              label: 'Cycle elapsed',
              value: (analysis.cycleProgress * 100).round().toString() + '%',
              progress: analysis.cycleProgress,
            ),
            if (analysis.isCurrent) ...[
              const Divider(height: 34),
              Row(
                children: [
                  Expanded(
                    child: _InlineFact(
                      label: 'Safe daily spend',
                      value: AppFormatters.money(
                        remainingPerDay,
                        currencyCode: controller.currencyCode,
                      ),
                    ),
                  ),
                  Container(
                    height: 38,
                    width: 1,
                    color: scheme.outlineVariant,
                  ),
                  Expanded(
                    child: _InlineFact(
                      label: 'Projected total',
                      value: AppFormatters.money(
                        analysis.projectedSpend,
                        currencyCode: controller.currencyCode,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PerformanceRow extends StatelessWidget {
  final String label;
  final String value;
  final double progress;

  const _PerformanceRow({
    required this.label,
    required this.value,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress,
          minHeight: 8,
          borderRadius: BorderRadius.circular(99),
        ),
      ],
    );
  }
}

class _InlineFact extends StatelessWidget {
  final String label;
  final String value;

  const _InlineFact({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyReportCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _EmptyReportCard({
    required this.icon,
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
        child: Column(
          children: [
            Icon(icon, size: 42, color: scheme.primary),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportAnalysis {
  final AppController controller;
  final _CycleSnapshot snapshot;
  final _CycleSnapshot previous;
  final List<_CycleSnapshot> previousThree;
  final bool isCurrent;

  _ReportAnalysis({
    required this.controller,
    required this.snapshot,
    required this.previous,
    required this.previousThree,
    required this.isCurrent,
  });

  double get savingsRate =>
      snapshot.income <= 0 ? 0 : snapshot.net / snapshot.income * 100;

  int get elapsedDays {
    if (!isCurrent) return snapshot.totalDays;
    final value = DateTime.now().difference(snapshot.start).inDays + 1;
    return value.clamp(1, snapshot.totalDays).toInt();
  }

  int get remainingDays =>
      math.max(0, snapshot.totalDays - elapsedDays).toInt();

  double get cycleProgress =>
      (elapsedDays / math.max(snapshot.totalDays, 1))
          .clamp(0.0, 1.0)
          .toDouble();

  double get dailyAverage =>
      elapsedDays <= 0 ? 0 : snapshot.spent / elapsedDays;

  double get projectedSpend {
    if (!isCurrent) return snapshot.spent;
    return dailyAverage * snapshot.totalDays;
  }

  double get remainingDailyAllowance {
    if (!isCurrent || remainingDays <= 0) return 0;
    final remaining = math.max(
      0.0,
      controller.monthlyBudget - snapshot.spent,
    ).toDouble();
    return remaining / remainingDays;
  }

  double? get previousChange {
    if (previous.spent <= 0) return null;
    return (snapshot.spent - previous.spent) / previous.spent * 100;
  }

  double get previousThreeAverage {
    final withData = previousThree.where((item) => item.spent > 0).toList();
    if (withData.isEmpty) return 0;
    return withData.fold<double>(0, (sum, item) => sum + item.spent) /
        withData.length;
  }

  double? get threeCycleChange {
    final average = previousThreeAverage;
    if (average <= 0) return null;
    return (snapshot.spent - average) / average * 100;
  }

  Map<String, double> get categoryTotals {
    final totals = <String, double>{};
    for (final item in snapshot.expenses) {
      totals[item.category] = (totals[item.category] ?? 0) + item.amount;
    }
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(entries);
  }

  MapEntry<String, double>? get topCategory {
    final totals = categoryTotals;
    return totals.isEmpty ? null : totals.entries.first;
  }

  Transaction? get biggestExpense {
    if (snapshot.expenses.isEmpty) return null;
    return snapshot.expenses.reduce(
      (a, b) => a.amount >= b.amount ? a : b,
    );
  }

  _BiggestDay? get biggestDay {
    if (snapshot.expenses.isEmpty) return null;
    final totals = <DateTime, double>{};
    for (final item in snapshot.expenses) {
      final key = DateTime(item.date.year, item.date.month, item.date.day);
      totals[key] = (totals[key] ?? 0) + item.amount;
    }
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return _BiggestDay(entries.first.key, entries.first.value);
  }

  List<FlSpot> get cumulativeSpending {
    final byDay = <int, double>{};
    for (final item in snapshot.expenses) {
      final index = item.date.difference(snapshot.start).inDays + 1;
      if (index < 1 || index > snapshot.totalDays) continue;
      byDay[index] = (byDay[index] ?? 0) + item.amount;
    }

    final limit = isCurrent ? elapsedDays : snapshot.totalDays;
    var running = 0.0;
    return [
      for (var day = 1; day <= math.max(1, limit); day++)
        FlSpot(day.toDouble(), running += byDay[day] ?? 0),
    ];
  }

  List<_Insight> get insights {
    if (snapshot.transactions.isEmpty) return const [];
    final result = <_Insight>[];

    if (previousChange != null) {
      final change = previousChange!;
      if (change <= -5) {
        result.add(
          _Insight(
            Icons.trending_down_rounded,
            'Spending is down',
            'You spent ' +
                change.abs().toStringAsFixed(0) +
                '% less than the previous cycle.',
            _InsightTone.good,
          ),
        );
      } else if (change >= 5) {
        result.add(
          _Insight(
            Icons.trending_up_rounded,
            'Spending is up',
            'You spent ' +
                change.toStringAsFixed(0) +
                '% more than the previous cycle.',
            _InsightTone.warning,
          ),
        );
      }
    }

    if (isCurrent && controller.monthlyBudget > 0) {
      if (projectedSpend > controller.monthlyBudget) {
        result.add(
          _Insight(
            Icons.speed_rounded,
            'Projected over budget',
            'At your current pace, spending may reach ' +
                AppFormatters.money(
                  projectedSpend,
                  currencyCode: controller.currencyCode,
                ) +
                '.',
            _InsightTone.warning,
          ),
        );
      } else {
        result.add(
          _Insight(
            Icons.verified_rounded,
            'Budget pace looks healthy',
            'Your current pace projects below the cycle budget.',
            _InsightTone.good,
          ),
        );
      }
    }

    final category = topCategory;
    if (category != null && snapshot.spent > 0) {
      final share = category.value / snapshot.spent * 100;
      result.add(
        _Insight(
          AppCategories.iconFor(
            category.key,
            iconKey: controller.categoryByName(category.key)?.iconKey,
          ),
          category.key + ' leads spending',
          category.key +
              ' represents ' +
              share.round().toString() +
              '% of expenses this cycle.',
          share >= 45 ? _InsightTone.warning : _InsightTone.neutral,
        ),
      );
    }

    if (snapshot.income > 0) {
      if (savingsRate >= 20) {
        result.add(
          _Insight(
            Icons.savings_rounded,
            'Strong savings rate',
            'You kept ' +
                savingsRate.toStringAsFixed(0) +
                '% of recorded income this cycle.',
            _InsightTone.good,
          ),
        );
      } else if (savingsRate < 0) {
        result.add(
          _Insight(
            Icons.account_balance_wallet_outlined,
            'Expenses exceed income',
            'Recorded spending is higher than recorded income for this cycle.',
            _InsightTone.warning,
          ),
        );
      }
    }

    return result.take(4).toList();
  }
}

class _CycleSnapshot {
  final DateTime start;
  final DateTime endExclusive;
  final List<Transaction> transactions;
  final List<Transaction> expenses;
  final List<Transaction> incomeTransactions;
  final double spent;
  final double income;

  const _CycleSnapshot({
    required this.start,
    required this.endExclusive,
    required this.transactions,
    required this.expenses,
    required this.incomeTransactions,
    required this.spent,
    required this.income,
  });

  double get net => income - spent;
  int get totalDays => endExclusive.difference(start).inDays;
}

class _Metric {
  final String label;
  final String value;
  final IconData icon;

  const _Metric(this.label, this.value, this.icon);
}

enum _InsightTone { good, warning, neutral }

class _Insight {
  final IconData icon;
  final String title;
  final String body;
  final _InsightTone tone;

  const _Insight(
    this.icon,
    this.title,
    this.body,
    this.tone,
  );
}

class _BiggestDay {
  final DateTime date;
  final double amount;

  const _BiggestDay(this.date, this.amount);
}

class _HighlightRow {
  final IconData icon;
  final String label;
  final String detail;
  final String value;

  const _HighlightRow(
    this.icon,
    this.label,
    this.detail,
    this.value,
  );
}
