class ReceiptScanResult {
  final String store;
  final double? amount;
  final String category;
  final DateTime? date;
  final String rawText;
  final double? taxAmount;
  final String? currencyCode;
  final String? receiptNumber;
  final double confidence;

  const ReceiptScanResult({
    required this.store,
    required this.amount,
    required this.category,
    required this.date,
    required this.rawText,
    this.taxAmount,
    this.currencyCode,
    this.receiptNumber,
    this.confidence = 0,
  });
}
