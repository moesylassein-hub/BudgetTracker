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

    test('start day is kept in safe 1 to 28 range', () {
      expect(BudgetCycle.normalizeStartDay(0), 1);
      expect(BudgetCycle.normalizeStartDay(31), 28);
    });
  });
}
