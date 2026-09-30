import 'package:budget_tracker/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transaction JSON round-trip preserves income type', () {
    final original = Transaction(
      id: '1',
      store: 'Freelance project',
      amount: 123.45,
      category: 'Freelance',
      date: DateTime(2026, 8, 21),
      note: 'Test note',
      type: TransactionType.income,
    );

    final restored = Transaction.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.store, original.store);
    expect(restored.amount, original.amount);
    expect(restored.category, original.category);
    expect(restored.date, original.date);
    expect(restored.note, original.note);
    expect(restored.type, TransactionType.income);
  });

  test('legacy JSON without a type defaults to expense', () {
    final restored = Transaction.fromJson({
      'id': 'legacy',
      'store': 'Old purchase',
      'amount': 50,
      'category': 'Other',
      'date': DateTime(2026, 8, 1).toIso8601String(),
      'note': '',
    });

    expect(restored.type, TransactionType.expense);
  });
}
