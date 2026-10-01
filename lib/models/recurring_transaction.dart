import 'transaction.dart';

enum RecurringFrequency {
  weekly,
  monthly;

  String get label => switch (this) {
        RecurringFrequency.weekly => 'Weekly',
        RecurringFrequency.monthly => 'Monthly',
      };

  static RecurringFrequency fromName(String? value) {
    return value == RecurringFrequency.weekly.name
        ? RecurringFrequency.weekly
        : RecurringFrequency.monthly;
  }
}

class RecurringTransaction {
  final String id;
  final String title;
  final double amount;
  final String category;
  final TransactionType type;
  final RecurringFrequency frequency;
  final DateTime startDate;
  final DateTime? endDate;
  final int dayOfMonth;
  final int weekday;
  final String note;
  final bool isActive;
  final DateTime? lastGeneratedOn;
  final DateTime createdAt;

  const RecurringTransaction({
    required this.id,
    required this.title,
    required this.amount,
    required this.category,
    required this.type,
    required this.frequency,
    required this.startDate,
    required this.dayOfMonth,
    required this.weekday,
    required this.createdAt,
    this.endDate,
    this.note = '',
    this.isActive = true,
    this.lastGeneratedOn,
  });

  bool get isIncome => type == TransactionType.income;
  bool get isExpense => type == TransactionType.expense;

  String occurrenceTransactionId(DateTime dueDate) {
    final date = _dateOnly(dueDate);
    final stamp =
        '${date.year.toString().padLeft(4, '0')}'
        '${date.month.toString().padLeft(2, '0')}'
        '${date.day.toString().padLeft(2, '0')}';
    return 'recurring_${id}_$stamp';
  }

  List<DateTime> dueDatesThrough(DateTime through) {
    if (!isActive) return const [];
    final end = _dateOnly(through);
    final start = _dateOnly(startDate);
    final effectiveEnd = endDate == null
        ? end
        : (_dateOnly(endDate!).isBefore(end) ? _dateOnly(endDate!) : end);
    if (effectiveEnd.isBefore(start)) return const [];

    final after = lastGeneratedOn == null
        ? start.subtract(const Duration(days: 1))
        : _dateOnly(lastGeneratedOn!);

    return switch (frequency) {
      RecurringFrequency.weekly => _weeklyDueDates(
          start: start,
          end: effectiveEnd,
          after: after,
        ),
      RecurringFrequency.monthly => _monthlyDueDates(
          start: start,
          end: effectiveEnd,
          after: after,
        ),
    };
  }

  DateTime? nextDueDate(DateTime reference) {
    if (!isActive) return null;
    final start = _dateOnly(startDate);
    final end = endDate == null ? null : _dateOnly(endDate!);
    var after = _dateOnly(reference);
    if (lastGeneratedOn != null && _dateOnly(lastGeneratedOn!).isAfter(after)) {
      after = _dateOnly(lastGeneratedOn!);
    }

    DateTime candidate;
    if (frequency == RecurringFrequency.weekly) {
      final targetWeekday =
          weekday.clamp(DateTime.monday, DateTime.sunday).toInt();
      var daysAhead = (targetWeekday - after.weekday) % 7;
      if (daysAhead == 0) daysAhead = 7;
      candidate = after.add(Duration(days: daysAhead));
      if (candidate.isBefore(start)) {
        final fromStart = (targetWeekday - start.weekday) % 7;
        candidate = start.add(Duration(days: fromStart));
      }
    } else {
      candidate = _monthlyOccurrence(after.year, after.month);
      if (!candidate.isAfter(after)) {
        final nextMonth = DateTime(after.year, after.month + 1, 1);
        candidate = _monthlyOccurrence(nextMonth.year, nextMonth.month);
      }
      if (candidate.isBefore(start)) {
        candidate = _monthlyOccurrence(start.year, start.month);
        if (candidate.isBefore(start)) {
          final nextMonth = DateTime(start.year, start.month + 1, 1);
          candidate = _monthlyOccurrence(nextMonth.year, nextMonth.month);
        }
      }
    }

    if (end != null && candidate.isAfter(end)) return null;
    return candidate;
  }

  RecurringTransaction copyWith({
    String? id,
    String? title,
    double? amount,
    String? category,
    TransactionType? type,
    RecurringFrequency? frequency,
    DateTime? startDate,
    DateTime? endDate,
    bool clearEndDate = false,
    int? dayOfMonth,
    int? weekday,
    String? note,
    bool? isActive,
    DateTime? lastGeneratedOn,
    bool clearLastGeneratedOn = false,
    DateTime? createdAt,
  }) {
    return RecurringTransaction(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      type: type ?? this.type,
      frequency: frequency ?? this.frequency,
      startDate: startDate ?? this.startDate,
      endDate: clearEndDate ? null : endDate ?? this.endDate,
      dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      weekday: weekday ?? this.weekday,
      note: note ?? this.note,
      isActive: isActive ?? this.isActive,
      lastGeneratedOn: clearLastGeneratedOn
          ? null
          : lastGeneratedOn ?? this.lastGeneratedOn,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'amount': amount,
        'category': category,
        'type': type.name,
        'frequency': frequency.name,
        'startDate': _dateOnly(startDate).toIso8601String(),
        'endDate': endDate == null ? null : _dateOnly(endDate!).toIso8601String(),
        'dayOfMonth': dayOfMonth,
        'weekday': weekday,
        'note': note,
        'isActive': isActive,
        'lastGeneratedOn': lastGeneratedOn == null
            ? null
            : _dateOnly(lastGeneratedOn!).toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };

  factory RecurringTransaction.fromJson(Map<String, dynamic> json) {
    final start =
        DateTime.tryParse(json['startDate'] as String? ?? '') ?? DateTime.now();
    return RecurringTransaction(
      id: json['id'] as String,
      title: (json['title'] as String?)?.trim().isNotEmpty == true
          ? (json['title'] as String).trim()
          : 'Recurring transaction',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      category: (json['category'] as String?) ?? '',
      type: TransactionType.fromName(json['type'] as String?),
      frequency: RecurringFrequency.fromName(json['frequency'] as String?),
      startDate: _dateOnly(start),
      endDate: DateTime.tryParse(json['endDate'] as String? ?? ''),
      dayOfMonth:
          ((json['dayOfMonth'] as num?)?.toInt() ?? start.day).clamp(1, 31).toInt(),
      weekday: ((json['weekday'] as num?)?.toInt() ?? start.weekday)
          .clamp(DateTime.monday, DateTime.sunday)
          .toInt(),
      note: (json['note'] as String?) ?? '',
      isActive: json['isActive'] as bool? ?? true,
      lastGeneratedOn:
          DateTime.tryParse(json['lastGeneratedOn'] as String? ?? ''),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }

  List<DateTime> _weeklyDueDates({
    required DateTime start,
    required DateTime end,
    required DateTime after,
  }) {
    final targetWeekday = weekday.clamp(DateTime.monday, DateTime.sunday);
    final offset = (targetWeekday - start.weekday) % 7;
    var cursor = start.add(Duration(days: offset));
    final result = <DateTime>[];
    while (!cursor.isAfter(end)) {
      if (cursor.isAfter(after)) result.add(cursor);
      cursor = cursor.add(const Duration(days: 7));
    }
    return result;
  }

  List<DateTime> _monthlyDueDates({
    required DateTime start,
    required DateTime end,
    required DateTime after,
  }) {
    final result = <DateTime>[];
    var cursor = DateTime(start.year, start.month, 1);
    final finalMonth = DateTime(end.year, end.month, 1);

    while (!cursor.isAfter(finalMonth)) {
      final occurrence = _monthlyOccurrence(cursor.year, cursor.month);
      if (!occurrence.isBefore(start) &&
          !occurrence.isAfter(end) &&
          occurrence.isAfter(after)) {
        result.add(occurrence);
      }
      cursor = DateTime(cursor.year, cursor.month + 1, 1);
    }
    return result;
  }

  DateTime _monthlyOccurrence(int year, int month) {
    final preferred = dayOfMonth.clamp(1, 31).toInt();
    final lastDay = DateTime(year, month + 1, 0).day;
    return DateTime(year, month, preferred.clamp(1, lastDay).toInt());
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
}
