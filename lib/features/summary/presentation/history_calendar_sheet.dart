import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/features/summary/data/summary_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Bottom-sheet calendar for browsing past Summary days.
///
/// Renders one month at a time as a 7-column grid. Days with logged activity
/// (any feed / pump / diaper / sleep / stash row) get a small dot under the
/// number — fed by [summaryActivityDaysProvider]. Future dates are disabled.
///
/// Tapping a day closes the sheet via `Navigator.pop(context, pickedDate)`
/// so the parent screen can update its `_selectedDate` and re-fetch.
///
/// Why custom instead of `CalendarDatePicker`: the framework's picker does
/// not expose a tile-builder, so per-day dot decorations require either a
/// private subclass or a separate package. A bespoke grid is ~150 lines and
/// keeps us on zero new dependencies.
class HistoryCalendarSheet extends ConsumerStatefulWidget {
  const HistoryCalendarSheet({
    super.key,
    required this.babyId,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });

  /// Baby whose activity index drives the dots.
  final String babyId;

  /// Date pre-selected when the sheet opens — controls which month is shown.
  final DateTime initialDate;

  /// Earliest selectable date (inclusive).
  final DateTime firstDate;

  /// Latest selectable date (inclusive) — typically today.
  final DateTime lastDate;

  @override
  ConsumerState<HistoryCalendarSheet> createState() =>
      _HistoryCalendarSheetState();
}

class _HistoryCalendarSheetState extends ConsumerState<HistoryCalendarSheet> {
  late DateTime _visibleMonth;

  static DateTime _firstOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

  @override
  void initState() {
    super.initState();
    _visibleMonth = _firstOfMonth(widget.initialDate);
  }

  bool _canGoPrevMonth() {
    final firstMonth = _firstOfMonth(widget.firstDate);
    return _visibleMonth.isAfter(firstMonth);
  }

  bool _canGoNextMonth() {
    final lastMonth = _firstOfMonth(widget.lastDate);
    return _visibleMonth.isBefore(lastMonth);
  }

  void _goPrevMonth() {
    if (!_canGoPrevMonth()) return;
    setState(() => _visibleMonth =
        DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1));
  }

  void _goNextMonth() {
    if (!_canGoNextMonth()) return;
    setState(() => _visibleMonth =
        DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final activityAsync = ref.watch(summaryActivityDaysProvider(
      (widget.babyId, _visibleMonth.year, _visibleMonth.month),
    ));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title row
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.summaryCalendarTitle,
                    style:
                        AppTypography.titleLarge(color: AppColors.inkPrimary),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: l10n.actionCancel,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            // Month header with prev/next
            Row(
              children: [
                IconButton(
                  key: const Key('history_cal_prev_month'),
                  icon: const Icon(Icons.chevron_left),
                  onPressed: _canGoPrevMonth() ? _goPrevMonth : null,
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      DateFormat('MMMM yyyy').format(_visibleMonth),
                      style: AppTypography.titleLarge(
                          color: AppColors.inkPrimary),
                    ),
                  ),
                ),
                IconButton(
                  key: const Key('history_cal_next_month'),
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _canGoNextMonth() ? _goNextMonth : null,
                ),
              ],
            ),

            // Weekday header
            _WeekdayHeader(),

            const SizedBox(height: AppSpacing.xs),

            // Day grid
            _DayGrid(
              visibleMonth: _visibleMonth,
              firstDate: widget.firstDate,
              lastDate: widget.lastDate,
              activityDays: activityAsync.value ?? const <String>{},
              onPick: (day) => Navigator.of(context).pop(day),
            ),

            if (activityAsync.value != null &&
                activityAsync.value!.isEmpty &&
                !activityAsync.isLoading)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  l10n.summaryCalendarNoData,
                  style:
                      AppTypography.bodyMedium(color: AppColors.inkSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Mon Tue Wed Thu Fri Sat Sun — driven by the device locale so Thai parents
/// see Thai labels, English parents see English. We use single-letter labels
/// so a 7-cell row never wraps on narrow phones.
class _WeekdayHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final firstDayOfWeek = MaterialLocalizations.of(context).firstDayOfWeekIndex;
    // Pick any week and rotate so day 0 of our labels matches firstDayOfWeek.
    final ref = DateTime(2024, 1, 7); // a Sunday
    final labels = List<String>.generate(7, (i) {
      final day = ref.add(Duration(days: (firstDayOfWeek + i) % 7));
      return DateFormat.E(locale).format(day);
    });
    return Row(
      children: labels
          .map((l) => Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Text(
                      l,
                      style: AppTypography.labelLarge(
                          color: AppColors.inkSecondary),
                    ),
                  ),
                ),
              ))
          .toList(growable: false),
    );
  }
}

class _DayGrid extends StatelessWidget {
  const _DayGrid({
    required this.visibleMonth,
    required this.firstDate,
    required this.lastDate,
    required this.activityDays,
    required this.onPick,
  });

  final DateTime visibleMonth;
  final DateTime firstDate;
  final DateTime lastDate;
  final Set<String> activityDays;
  final ValueChanged<DateTime> onPick;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final firstDayOfWeek = MaterialLocalizations.of(context).firstDayOfWeekIndex;
    final firstOfMonth = DateTime(visibleMonth.year, visibleMonth.month, 1);
    // SQLite DateTime.weekday: Mon=1..Sun=7. We rotate so column 0 aligns
    // with the locale's first day of week (US=Sun, TH=Mon, etc).
    final lead = (firstOfMonth.weekday - 1 - firstDayOfWeek + 7) % 7;
    final daysInMonth =
        DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final totalCells = lead + daysInMonth;
    final rows = (totalCells / 7).ceil();

    final today = _dateOnly(DateTime.now());

    return Column(
      children: List<Widget>.generate(rows, (rowIdx) {
        return Row(
          children: List<Widget>.generate(7, (colIdx) {
            final cellIdx = rowIdx * 7 + colIdx;
            final dayNum = cellIdx - lead + 1;
            if (dayNum < 1 || dayNum > daysInMonth) {
              return const Expanded(child: SizedBox(height: 48));
            }
            final date =
                DateTime(visibleMonth.year, visibleMonth.month, dayNum);
            final dateStr = _yyyyMmDd(date);
            final isFuture = date.isAfter(lastDate);
            final isBeforeFirst = date.isBefore(firstDate);
            final disabled = isFuture || isBeforeFirst;
            final isToday = _dateOnly(date) == today;
            final hasActivity = activityDays.contains(dateStr);

            return Expanded(
              child: _DayCell(
                key: ValueKey('history_cal_day_$dateStr'),
                dayNum: dayNum,
                isToday: isToday,
                hasActivity: hasActivity,
                disabled: disabled,
                onTap: disabled ? null : () => onPick(date),
              ),
            );
          }),
        );
      }),
    );
  }

  static String _yyyyMmDd(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    super.key,
    required this.dayNum,
    required this.isToday,
    required this.hasActivity,
    required this.disabled,
    required this.onTap,
  });

  final int dayNum;
  final bool isToday;
  final bool hasActivity;
  final bool disabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final numberColor = disabled
        ? AppColors.inkSecondary.withValues(alpha: 0.4)
        : (isToday ? scheme.primary : AppColors.inkPrimary);

    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: SizedBox(
        height: 48,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: isToday
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.primary, width: 1.5),
                    )
                  : null,
              child: Text(
                '$dayNum',
                style: AppTypography.bodyMedium(color: numberColor),
              ),
            ),
            SizedBox(
              height: 6,
              child: hasActivity
                  ? Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: disabled
                            ? AppColors.inkSecondary.withValues(alpha: 0.3)
                            : scheme.primary,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
