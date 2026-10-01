import 'package:budget_tracker/models/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('refund editing and JSON preserve signed expense and cash flow', () {
    final purchase = Transaction(
      id: 'refund',
      store: 'Travel',
      amount: 800,
      category: 'Travel',
      date: DateTime(2026, 10, 1),
    );
    final refund = Transaction.fromJson(
      purchase.copyWith(amount: -800).toJson(),
    );
    expect(refund.amount, -800);
    expect(refund.isExpense, isTrue);
    expect(refund.isIncome, isFalse);
    expect(refund.cashFlow, 800);
    expect(purchase.cashFlow, -800);
  });

  test(
      'amount validation permits only finite nonzero expenses and positive income',
      () {
    for (final value in [
      '0',
      '-0',
      'NaN',
      'Infinity',
      '-Infinity',
      '',
      'abc',
      '100000000',
      '-100000000',
    ]) {
      expect(
        TransactionType.expense.validateAmount(value),
        isNotNull,
        reason: value,
      );
    }
    expect(TransactionType.expense.validateAmount('-800.50'), isNull);
    expect(TransactionType.expense.validateAmount('800.50'), isNull);
    expect(TransactionType.income.validateAmount('-800.50'), isNotNull);
    expect(TransactionType.income.validateAmount('800.50'), isNull);
  });

  test('transaction JSON round-trip preserves income type', () {
    final original = Transaction(
      id: '1',
      store: 'Freelance project',
      amount: 123.45,
      category: 'Freelance',
      date: DateTime(2026, 8, 21),
      note: 'Test note',
      ledger: 'Main Wallet',
      account: 'Bank',
      currencyCode: 'USD',
      type: TransactionType.income,
    );

    final restored = Transaction.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.store, original.store);
    expect(restored.amount, original.amount);
    expect(restored.category, original.category);
    expect(restored.date, original.date);
    expect(restored.note, original.note);
    expect(restored.ledger, original.ledger);
    expect(restored.account, original.account);
    expect(restored.currencyCode, original.currencyCode);
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
    expect(restored.ledger, isEmpty);
    expect(restored.account, isEmpty);
    expect(restored.currencyCode, isEmpty);
  });
}
