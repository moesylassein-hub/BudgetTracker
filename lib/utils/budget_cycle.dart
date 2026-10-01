class BudgetCycle {
  static int normalizeStartDay(int value) => value.clamp(1, 28);

  static DateTime startFor(DateTime reference, int startDay) {
    final day = normalizeStartDay(startDay);
    final thisMonthStart = DateTime(reference.year, reference.month, day);
    if (reference.isBefore(thisMonthStart)) {
      return DateTime(reference.year, reference.month - 1, day);
    }
    return thisMonthStart;
  }

  static DateTime endExclusiveFor(DateTime reference, int startDay) {
    final start = startFor(reference, startDay);
    return DateTime(start.year, start.month + 1, normalizeStartDay(startDay));
  }

  static double progress(DateTime reference, int startDay) {
    final start = startFor(reference, startDay);
    final end = endExclusiveFor(reference, startDay);
    final totalDays = end.difference(start).inDays;
    if (totalDays <= 0) return 1;

    final elapsedDays = reference.difference(start).inDays + 1;
    return (elapsedDays / totalDays).clamp(0.0, 1.0).toDouble();
  }
}
