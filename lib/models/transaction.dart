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
  final TransactionType type;

  const Transaction({
    required this.id,
    required this.store,
    required this.amount,
    required this.category,
    required this.date,
    this.note = '',
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
    TransactionType? type,
  }) {
    return Transaction(
      id: id ?? this.id,
      store: store ?? this.store,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      date: date ?? this.date,
      note: note ?? this.note,
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
      type: TransactionType.fromName(json['type'] as String?),
    );
  }
}
