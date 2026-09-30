import 'package:budget_tracker/services/receipt_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ReceiptParser', () {
    test('extracts merchant, total, currency and date', () {
      const receipt = '''
CARREFOUR
Tax Invoice
21/08/2026
Milk 65.00
Bread 30.00
SUBTOTAL 95.00
TOTAL EGP 95.00
''';

      final result = ReceiptParser().parse(receipt);

      expect(result.store, 'Carrefour');
      expect(result.amount, 95.00);
      expect(result.currencyCode, 'EGP');
      expect(result.category, 'Food');
      expect(result.date, DateTime(2026, 8, 21));
    });

    test('prefers grand total over subtotal and detects tax', () {
      const receipt = '''
Coffee House
Subtotal 125.00
VAT 17.50
Grand Total 142.50
''';

      final result = ReceiptParser().parse(receipt);
      expect(result.amount, 142.50);
      expect(result.taxAmount, 17.50);
    });

    test('accepts an integer on a clearly labeled total line', () {
      const receipt = '''
Local Market
Milk 40.00
Bread 35.00
TOTAL EGP 75
''';

      final result = ReceiptParser().parse(receipt);
      expect(result.amount, 75);
    });

    test('detects receipt number', () {
      const receipt = '''
Example Store
Receipt No: A123-456
Total USD 15.99
''';
      final result = ReceiptParser().parse(receipt);
      expect(result.receiptNumber, 'A123-456');
      expect(result.currencyCode, 'USD');
    });
  });
}
