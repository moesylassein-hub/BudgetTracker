import 'package:flutter/material.dart';

import '../utils/formatters.dart';

/// A neutral ring keeps the chart visible without inventing a spending slice.
class EmptySpendingDonut extends StatelessWidget {
  final double netSpending;
  final String currencyCode;

  const EmptySpendingDonut({
    super.key,
    required this.netSpending,
    required this.currencyCode,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: 'Empty spending chart',
          child: SizedBox.square(
            dimension: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(width: 32, color: scheme.outlineVariant),
                  ),
                ),
                SizedBox(
                  width: 140,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Net spending',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          AppFormatters.compactMoney(
                            netSpending,
                            currencyCode: currencyCode,
                          ),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'No positive category spending',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
