enum TransactionType {
  expense,
  income;

  String get label => this == TransactionType.expense ? 'Expense' : 'Income';

  static TransactionType fromName(String? value) {
    return value == TransactionType.income.name
        ? TransactionType.income
        : TransactionType.expense;
  }
}

class Transaction {
  final String id;
  final String store;
  final double amount;
  final String category;
  final DateTime date;
  final String note;
  final String ledger;
  final String account;
  final String currencyCode;
  final TransactionType type;

  const Transaction({
    required this.id,
    required this.store,
    required this.amount,
    required this.category,
    required this.date,
    this.note = '',
    this.ledger = '',
    this.account = '',
    this.currencyCode = '',
    this.type = TransactionType.expense,
  });

  bool get isExpense => type == TransactionType.expense;
  bool get isIncome => type == TransactionType.income;

  Transaction copyWith({
    String? id,
    String? store,
    double? amount,
    String? category,
    DateTime? date,
    String? note,
    String? ledger,
    String? account,
    String? currencyCode,
    TransactionType? type,
  }) {
    return Transaction(
      id: id ?? this.id,
      store: store ?? this.store,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      date: date ?? this.date,
      note: note ?? this.note,
      ledger: ledger ?? this.ledger,
      account: account ?? this.account,
      currencyCode: currencyCode ?? this.currencyCode,
      type: type ?? this.type,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'store': store,
        'amount': amount,
        'category': category,
        'date': date.toIso8601String(),
        'note': note,
        'ledger': ledger,
        'account': account,
        'currencyCode': currencyCode,
        'type': type.name,
      };

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'] as String,
      store: json['store'] as String,
      amount: (json['amount'] as num).toDouble(),
      category: (json['category'] as String?) ?? 'Other',
      date: DateTime.parse(json['date'] as String),
      note: (json['note'] as String?) ?? '',
      ledger: (json['ledger'] as String?) ?? '',
      account: (json['account'] as String?) ?? '',
      currencyCode: (json['currencyCode'] as String?) ?? '',
      type: TransactionType.fromName(json['type'] as String?),
    );
  }
}
