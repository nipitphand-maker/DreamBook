/// Returns the [DateTime] range `[start, end)` for the logical day that
/// contains [date], given a [dayStartHour] in local time.
///
/// Example: date = 2026-05-16, dayStartHour = 6
///   → start = 2026-05-16T06:00:00, end = 2026-05-17T06:00:00
///
/// A session started at 03:00 on 2026-05-16 falls BEFORE start, so it
/// belongs to the previous logical day (2026-05-15).
(DateTime start, DateTime end) logicalDayBounds(DateTime date, int dayStartHour) {
  if (date.isUtc) {
    final start = DateTime.utc(date.year, date.month, date.day, dayStartHour);
    final end = DateTime.utc(date.year, date.month, date.day + 1, dayStartHour);
    return (start, end);
  }
  final start = DateTime(date.year, date.month, date.day, dayStartHour);
  final nextDay = DateTime(date.year, date.month, date.day).add(const Duration(days: 1));
  final end = DateTime(nextDay.year, nextDay.month, nextDay.day, dayStartHour);
  return (start, end);
}
