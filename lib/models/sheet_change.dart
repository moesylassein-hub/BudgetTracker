import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'budget_category.dart';
import 'recurring_transaction.dart';
import 'savings_goal.dart';
import 'transaction.dart';

String newChangeId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256),
).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

String canonicalJson(Object? value) {
  Object? sort(Object? item) {
    if (item is Map) {
      final keys = item.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: sort(item[key])};
    }
    if (item is List) return item.map(sort).toList();
    return item;
  }

  return jsonEncode(sort(value));
}

/// Immutable app changes are appended. A hash also detects direct cell edits.
class SheetChange {
  static const columns = [
    'Change ID',
    'Item',
    'Replaces',
    'Editor',
    'Date',
    'Type',
    'Merchant',
    'Category',
    'Amount',
    'Note',
    'Ledger',
    'Account',
    'Currency',
    'Details',
    'Deleted',
  ];
  final String id;
  final String entity;
  final List<String> parents;
  final String author;
  final Map<String, dynamic>? value;

  SheetChange({
    required this.id,
    required this.entity,
    required this.parents,
    required this.author,
    required this.value,
  });

  String get revision =>
      sha256.convert(utf8.encode(canonicalJson(toJson()))).toString();
  Map<String, dynamic> toJson() => {
    'id': id,
    'entity': entity,
    'parents': parents,
    'author': author,
    'value': value,
  };
  factory SheetChange.fromJson(Map<String, dynamic> json) => SheetChange(
    id: json['id'] as String,
    entity: json['entity'] as String,
    parents: (json['parents'] as List).cast<String>(),
    author: json['author'] as String,
    value: json['value'] == null
        ? null
        : Map<String, dynamic>.from(json['value'] as Map),
  );

  List<Object> toRow() {
    final tx = entity.startsWith('transaction:') ? value : null;
    return [
      id,
      entity,
      jsonEncode(parents),
      author,
      tx?['date'] ?? '',
      tx?['type'] ?? '',
      tx?['store'] ?? '',
      tx?['category'] ?? '',
      tx?['amount'] ?? '',
      tx?['note'] ?? '',
      tx?['ledger'] ?? '',
      tx?['account'] ?? '',
      tx?['currencyCode'] ?? '',
      tx == null && value != null ? canonicalJson(value) : '',
      value == null,
    ];
  }

  factory SheetChange.fromRow(List<dynamic> row) {
    String cell(int index) => index < row.length ? '${row[index]}' : '';
    final id = cell(0);
    final entity = cell(1);
    if (id.isEmpty || entity.isEmpty) {
      throw const FormatException('Missing change or item ID.');
    }
    final parents = (jsonDecode(cell(2)) as List).cast<String>();
    final deleted = cell(14).toLowerCase();
    if (deleted != 'true' && deleted != 'false') {
      throw const FormatException('Deleted must be TRUE or FALSE.');
    }
    Map<String, dynamic>? value;
    if (deleted != 'true') {
      if (entity.startsWith('transaction:')) {
        value = Transaction(
          id: entity.substring('transaction:'.length),
          date: DateTime.parse(cell(4)),
          type: TransactionType.fromName(cell(5)),
          store: cell(6),
          category: cell(7),
          amount: double.parse(cell(8)),
          note: cell(9),
          ledger: cell(10),
          account: cell(11),
          currencyCode: cell(12),
        ).toJson();
        if (!['expense', 'income'].contains(cell(5))) {
          throw const FormatException('Type must be expense or income.');
        }
      } else {
        value = Map<String, dynamic>.from(jsonDecode(cell(13)) as Map);
      }
    }
    final change = SheetChange(
      id: id,
      entity: entity,
      parents: parents,
      author: cell(3),
      value: value,
    );
    change.validate();
    return change;
  }

  void validate() {
    final parts = entity.split(':');
    if (parts.length != 2 || parts.last.isEmpty) {
      throw const FormatException('Invalid item ID.');
    }
    if (![
      'transaction',
      'category',
      'goal',
      'recurring',
      'setting',
    ].contains(parts.first)) {
      throw const FormatException('Unknown item type.');
    }
    if (parents.any((parent) => !RegExp(r'^[a-f0-9]{64}$').hasMatch(parent))) {
      throw const FormatException('Invalid revision history.');
    }
    if (value == null) return;
    if (parts.first != 'setting' && value!['id'] != parts.last) {
      throw const FormatException('Item ID does not match its data.');
    }
    switch (parts.first) {
      case 'transaction':
        final tx = Transaction.fromJson(value!);
        if (!tx.type.acceptsAmount(tx.amount) ||
            tx.amount.abs() > 99999999 ||
            tx.store.trim().isEmpty ||
            tx.category.trim().isEmpty) {
          throw const FormatException(
            'Invalid transaction amount, merchant or category.',
          );
        }
      case 'category':
        final category = BudgetCategory.fromJson(value!);
        if (category.name.trim().isEmpty ||
            (category.monthlyBudget != null &&
                (!category.monthlyBudget!.isFinite ||
                    category.monthlyBudget! < 0))) {
          throw const FormatException('Invalid category.');
        }
      case 'goal':
        final goal = SavingsGoal.fromJson(value!);
        if (!goal.targetAmount.isFinite ||
            goal.targetAmount <= 0 ||
            !goal.savedAmount.isFinite ||
            goal.savedAmount < 0) {
          throw const FormatException('Invalid savings goal.');
        }
      case 'recurring':
        final rule = RecurringTransaction.fromJson(value!);
        if (!rule.type.acceptsAmount(rule.amount) ||
            rule.amount.abs() > 99999999) {
          throw const FormatException('Invalid recurring amount.');
        }
      case 'setting':
        final v = value!['value'];
        final valid = switch (parts.last) {
          'monthlyBudget' => v is num && v.isFinite && v > 0,
          'currencyCode' => v is String && RegExp(r'^[A-Z]{3}$').hasMatch(v),
          'budgetCycleStartDay' => v is int && v >= 1 && v <= 31,
          _ => false,
        };
        if (!valid) {
          throw const FormatException('Invalid shared budget setting.');
        }
    }
  }
}

/// A version graph preserves concurrent branches until a person resolves them.
class SheetLedger {
  final Map<String, SheetChange> changes = {};
  void addAll(Iterable<SheetChange> values) {
    final next = Map<String, SheetChange>.from(changes);
    for (final change in values) {
      change.validate();
      next[change.revision] = change;
    }
    for (final change in next.values) {
      for (final parent in change.parents) {
        if (next.containsKey(parent) && next[parent]!.entity != change.entity) {
          throw const FormatException(
            'Revision history references a different item.',
          );
        }
      }
    }
    changes
      ..clear()
      ..addAll(next);
  }

  Map<String, List<SheetChange>> get heads {
    final superseded = changes.values
        .expand((change) => change.parents)
        .toSet();
    final result = <String, List<SheetChange>>{};
    for (final entry in changes.entries) {
      if (!superseded.contains(entry.key)) {
        result.putIfAbsent(entry.value.entity, () => []).add(entry.value);
      }
    }
    // Identical recurring occurrences created on two devices are equivalent.
    for (final entries in result.values) {
      entries.sort((a, b) => a.revision.compareTo(b.revision));
    }
    return result;
  }

  Map<String, List<SheetChange>> get conflicts => Map.fromEntries(
    heads.entries.where(
      (entry) =>
          entry.value
              .map((change) => canonicalJson(change.value))
              .toSet()
              .length >
          1,
    ),
  );

  Map<String, Map<String, dynamic>> get entities => {
    for (final entry in heads.entries)
      if (entry.value.last.value != null) entry.key: entry.value.last.value!,
  };

  static Map<String, Map<String, dynamic>> flatten(
    Map<String, dynamic> snapshot,
  ) => {
    for (final pair in {
      'transactions': 'transaction',
      'categories': 'category',
      'goals': 'goal',
      'recurringTransactions': 'recurring',
    }.entries)
      for (final raw in snapshot[pair.key] as List? ?? [])
        '${pair.value}:${raw['id']}': Map<String, dynamic>.from(raw as Map),
    for (final key in ['monthlyBudget', 'currencyCode', 'budgetCycleStartDay'])
      'setting:$key': {'value': snapshot[key]},
  };

  Map<String, dynamic> snapshot(Map<String, dynamic> localPreferences) {
    final values = entities;
    return {
      ...localPreferences,
      for (final pair in {
        'transactions': 'transaction',
        'categories': 'category',
        'goals': 'goal',
        'recurringTransactions': 'recurring',
      }.entries)
        pair.key: values.entries
            .where((entry) => entry.key.startsWith('${pair.value}:'))
            .map((entry) => entry.value)
            .toList(),
      for (final key in [
        'monthlyBudget',
        'currencyCode',
        'budgetCycleStartDay',
      ])
        if (values.containsKey('setting:$key'))
          key: values['setting:$key']!['value'],
    };
  }

  List<SheetChange> edits(Map<String, dynamic> snapshot, String author) {
    final desired = flatten(snapshot);
    final current = entities;
    final versions = heads;
    final edits = <SheetChange>[];
    for (final key in {...desired.keys, ...current.keys}) {
      if (canonicalJson(desired[key]) == canonicalJson(current[key])) continue;
      final old = versions[key] ?? [];
      edits.add(
        SheetChange(
          id: newChangeId(),
          entity: key,
          // Ordinary editing doesn't silently resolve another editor's branch.
          parents:
              old.map((change) => canonicalJson(change.value)).toSet().length <=
                  1
              ? old.map((change) => change.revision).toList()
              : [old.last.revision],
          author: author,
          value: desired[key],
        ),
      );
    }
    return edits;
  }
}
