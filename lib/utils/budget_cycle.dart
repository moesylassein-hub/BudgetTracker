class BudgetCycle {
  static int normalizeStartDay(int value) => value.clamp(1, 31).toInt();

  static DateTime startFor(DateTime reference, int startDay) {
    final day = normalizeStartDay(startDay);
    final thisMonthStart = DateTime(
      reference.year,
      reference.month,
      _effectiveDay(reference.year, reference.month, day),
    );
    if (reference.isBefore(thisMonthStart)) {
      final previousMonth = DateTime(reference.year, reference.month - 1, 1);
      return DateTime(
        previousMonth.year,
        previousMonth.month,
        _effectiveDay(previousMonth.year, previousMonth.month, day),
      );
    }
    return thisMonthStart;
  }

  static DateTime endExclusiveFor(DateTime reference, int startDay) {
    final start = startFor(reference, startDay);
    final nextMonth = DateTime(start.year, start.month + 1, 1);
    final day = normalizeStartDay(startDay);
    return DateTime(
      nextMonth.year,
      nextMonth.month,
      _effectiveDay(nextMonth.year, nextMonth.month, day),
    );
  }

  static double progress(DateTime reference, int startDay) {
    final start = startFor(reference, startDay);
    final end = endExclusiveFor(reference, startDay);
    final totalDays = end.difference(start).inDays;
    if (totalDays <= 0) return 1;

    final elapsedDays = reference.difference(start).inDays + 1;
    return (elapsedDays / totalDays).clamp(0.0, 1.0).toDouble();
  }

  static int _effectiveDay(int year, int month, int preferredDay) {
    final lastDay = DateTime(year, month + 1, 0).day;
    return preferredDay.clamp(1, lastDay).toInt();
  }
}
