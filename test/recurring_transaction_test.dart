import 'package:budget_tracker/models/recurring_transaction.dart';
import 'package:budget_tracker/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  RecurringTransaction monthlyRule({
    int day = 25,
    DateTime? start,
    DateTime? end,
    DateTime? lastGeneratedOn,
    bool active = true,
  }) {
    return RecurringTransaction(
      id: 'salary',
      title: 'Salary',
      amount: 15000,
      category: 'Salary',
      type: TransactionType.income,
      frequency: RecurringFrequency.monthly,
      startDate: start ?? DateTime(2026, 9, 25),
      endDate: end,
      dayOfMonth: day,
      weekday: DateTime.friday,
      isActive: active,
      lastGeneratedOn: lastGeneratedOn,
      createdAt: DateTime(2026, 9, 1),
    );
  }

  group('RecurringTransaction monthly schedule', () {
    test('catches up every missed monthly occurrence once', () {
      final rule = monthlyRule();
      expect(
        rule.dueDatesThrough(DateTime(2026, 11, 30)),
        [
          DateTime(2026, 9, 25),
          DateTime(2026, 10, 25),
          DateTime(2026, 11, 25),
        ],
      );

      final processed = rule.copyWith(
        lastGeneratedOn: DateTime(2026, 10, 25),
      );
      expect(
        processed.dueDatesThrough(DateTime(2026, 11, 30)),
        [DateTime(2026, 11, 25)],
      );
    });

    test('day 31 uses the final valid day in short months', () {
      final rule = monthlyRule(
        day: 31,
        start: DateTime(2027, 1, 31),
      );

      expect(
        rule.dueDatesThrough(DateTime(2027, 3, 31)),
        [
          DateTime(2027, 1, 31),
          DateTime(2027, 2, 28),
          DateTime(2027, 3, 31),
        ],
      );
    });

    test('leap-year February is handled correctly', () {
      final rule = monthlyRule(
        day: 31,
        start: DateTime(2028, 1, 31),
      );

      expect(
        rule.dueDatesThrough(DateTime(2028, 2, 29)),
        [
          DateTime(2028, 1, 31),
          DateTime(2028, 2, 29),
        ],
      );
    });

    test('end date prevents later occurrences', () {
      final rule = monthlyRule(
        end: DateTime(2026, 10, 25),
      );

      expect(
        rule.dueDatesThrough(DateTime(2027, 1, 1)),
        [
          DateTime(2026, 9, 25),
          DateTime(2026, 10, 25),
        ],
      );
    });

    test('paused rule creates nothing', () {
      final rule = monthlyRule(active: false);
      expect(rule.dueDatesThrough(DateTime(2027, 1, 1)), isEmpty);
    });

    test('occurrence IDs are deterministic per due date', () {
      final rule = monthlyRule();
      expect(
        rule.occurrenceTransactionId(DateTime(2026, 9, 25)),
        'recurring_salary_20260925',
      );
      expect(
        rule.occurrenceTransactionId(DateTime(2026, 9, 25, 23, 59)),
        'recurring_salary_20260925',
      );
    });
  });

  group('RecurringTransaction weekly schedule', () {
    test('creates the selected weekday only', () {
      final rule = RecurringTransaction(
        id: 'allowance',
        title: 'Allowance',
        amount: 500,
        category: 'Other Income',
        type: TransactionType.income,
        frequency: RecurringFrequency.weekly,
        startDate: DateTime(2026, 10, 1),
        dayOfMonth: 1,
        weekday: DateTime.friday,
        createdAt: DateTime(2026, 10, 1),
      );

      expect(
        rule.dueDatesThrough(DateTime(2026, 10, 16)),
        [
          DateTime(2026, 10, 2),
          DateTime(2026, 10, 9),
          DateTime(2026, 10, 16),
        ],
      );
    });
  });
}
