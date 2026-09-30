import 'transaction.dart';

class BudgetCategory {
  final String id;
  final String name;
  final String iconKey;
  final TransactionType type;
  final double? monthlyBudget;

  const BudgetCategory({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.type,
    this.monthlyBudget,
  });

  BudgetCategory copyWith({
    String? id,
    String? name,
    String? iconKey,
    TransactionType? type,
    double? monthlyBudget,
    bool clearBudget = false,
  }) {
    return BudgetCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      iconKey: iconKey ?? this.iconKey,
      type: type ?? this.type,
      monthlyBudget: clearBudget ? null : monthlyBudget ?? this.monthlyBudget,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'iconKey': iconKey,
        'type': type.name,
        'monthlyBudget': monthlyBudget,
      };

  factory BudgetCategory.fromJson(Map<String, dynamic> json) {
    return BudgetCategory(
      id: json['id'] as String,
      name: json['name'] as String,
      iconKey: (json['iconKey'] as String?) ?? 'category',
      type: TransactionType.fromName(json['type'] as String?),
      monthlyBudget: (json['monthlyBudget'] as num?)?.toDouble(),
    );
  }

  static List<BudgetCategory> get defaults => const [
        BudgetCategory(id: 'expense-food', name: 'Food', iconKey: 'restaurant', type: TransactionType.expense),
        BudgetCategory(id: 'expense-transport', name: 'Transport', iconKey: 'car', type: TransactionType.expense),
        BudgetCategory(id: 'expense-shopping', name: 'Shopping', iconKey: 'shopping', type: TransactionType.expense),
        BudgetCategory(id: 'expense-bills', name: 'Bills', iconKey: 'receipt', type: TransactionType.expense),
        BudgetCategory(id: 'expense-entertainment', name: 'Entertainment', iconKey: 'movie', type: TransactionType.expense),
        BudgetCategory(id: 'expense-health', name: 'Health', iconKey: 'health', type: TransactionType.expense),
        BudgetCategory(id: 'expense-education', name: 'Education', iconKey: 'school', type: TransactionType.expense),
        BudgetCategory(id: 'expense-other', name: 'Other', iconKey: 'category', type: TransactionType.expense),
        BudgetCategory(id: 'income-salary', name: 'Salary', iconKey: 'salary', type: TransactionType.income),
        BudgetCategory(id: 'income-freelance', name: 'Freelance', iconKey: 'work', type: TransactionType.income),
        BudgetCategory(id: 'income-refunds', name: 'Refunds', iconKey: 'refund', type: TransactionType.income),
        BudgetCategory(id: 'income-gifts', name: 'Gifts', iconKey: 'gift', type: TransactionType.income),
        BudgetCategory(id: 'income-other', name: 'Other Income', iconKey: 'income', type: TransactionType.income),
      ];
}
