import 'package:flutter/material.dart';

import '../utils/formatters.dart';

class BudgetCard extends StatelessWidget {
  final double budget;
  final double spent;
  final String currencyCode;

  const BudgetCard({
    super.key,
    required this.budget,
    required this.spent,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = budget - spent;
    final rawProgress = budget <= 0 ? 0.0 : spent / budget;
    final progress = rawProgress.clamp(0.0, 1.0).toDouble();
    final overBudget = remaining < 0;
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, scheme.tertiary, 0.45)!,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Monthly budget',
                style: TextStyle(
                  color: scheme.onPrimary.withValues(alpha: 0.82),
                  fontWeight: FontWeight.w700,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.onPrimary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  AppFormatters.month(DateTime.now()),
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            AppFormatters.money(remaining.abs(), currencyCode: currencyCode),
            style: TextStyle(
              color: scheme.onPrimary,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.2,
            ),
          ),
          Text(
            overBudget ? 'over budget' : 'left to spend',
            style: TextStyle(color: scheme.onPrimary.withValues(alpha: 0.82)),
          ),
          const SizedBox(height: 22),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              backgroundColor: scheme.onPrimary.withValues(alpha: 0.18),
              valueColor: AlwaysStoppedAnimation<Color>(scheme.onPrimary),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${AppFormatters.money(spent, currencyCode: currencyCode)} spent',
                style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w700),
              ),
              Text(
                '${(rawProgress * 100).round()}%',
                style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
