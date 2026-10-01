import 'package:budget_tracker/utils/budget_cycle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BudgetCycle', () {
    test('cycle can start on salary day before calendar month', () {
      expect(
        BudgetCycle.startFor(DateTime(2026, 10, 1), 25),
        DateTime(2026, 9, 25),
      );
      expect(
        BudgetCycle.endExclusiveFor(DateTime(2026, 10, 1), 25),
        DateTime(2026, 10, 25),
      );
    });

    test('date after start day belongs to next salary cycle', () {
      expect(
        BudgetCycle.startFor(DateTime(2026, 10, 30), 25),
        DateTime(2026, 10, 25),
      );
      expect(
        BudgetCycle.endExclusiveFor(DateTime(2026, 10, 30), 25),
        DateTime(2026, 11, 25),
      );
    });

    test('supports start days up to 31', () {
      expect(BudgetCycle.normalizeStartDay(0), 1);
      expect(BudgetCycle.normalizeStartDay(31), 31);
      expect(BudgetCycle.normalizeStartDay(40), 31);
    });

    test('day 31 falls back to the last day of shorter months', () {
      expect(
        BudgetCycle.startFor(DateTime(2026, 3, 15), 31),
        DateTime(2026, 2, 28),
      );
      expect(
        BudgetCycle.endExclusiveFor(DateTime(2026, 3, 15), 31),
        DateTime(2026, 3, 31),
      );
    });

    test('day 30 handles leap-year February correctly', () {
      expect(
        BudgetCycle.startFor(DateTime(2028, 3, 1), 30),
        DateTime(2028, 2, 29),
      );
      expect(
        BudgetCycle.endExclusiveFor(DateTime(2028, 3, 1), 30),
        DateTime(2028, 3, 30),
      );
    });
  });
}
