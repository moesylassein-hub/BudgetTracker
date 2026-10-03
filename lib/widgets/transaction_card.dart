import 'package:flutter/material.dart';

import '../models/transaction.dart';
import '../utils/app_categories.dart';
import '../utils/formatters.dart';

class TransactionCard extends StatelessWidget {
  final Transaction transaction;
  final String currencyCode;
  final String? iconKey;
  final String? authorship;
  final VoidCallback? onTap;

  const TransactionCard({
    super.key,
    required this.transaction,
    required this.currencyCode,
    this.iconKey,
    this.authorship,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final categoryColor = AppCategories.colorFor(transaction.category, scheme);
    final color = transaction.isIncome ? scheme.tertiary : categoryColor;
    final displayCurrency = transaction.currencyCode.isEmpty
        ? currencyCode
        : transaction.currencyCode;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Icon(
                  AppCategories.iconFor(transaction.category, iconKey: iconKey),
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      transaction.store,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${transaction.category} • ${AppFormatters.shortDate(transaction.date)}',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    if (authorship != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        authorship!,
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${transaction.cashFlow >= 0 ? '+' : '-'}${AppFormatters.money(transaction.amount.abs(), currencyCode: displayCurrency)}',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: transaction.cashFlow > 0 ? scheme.tertiary : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
