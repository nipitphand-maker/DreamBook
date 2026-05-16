import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// A time-entry widget with a 2-button + chip pattern.
///
/// **State 1 — no time selected ([value] == null):**
/// Shows two side-by-side buttons: "Today" (time picker only) and "Past date"
/// (date + time picker).
///
/// **State 2 — time selected ([value] != null):**
/// Shows a single chip with formatted time and an × button that resets to
/// null.
///
/// Format rules:
///   - today  → "2:30 PM"
///   - other  → "Mon, 2:30 PM"
class LoggedAtChip extends StatelessWidget {
  const LoggedAtChip({
    super.key,
    required this.value,
    required this.onTapToday,
    required this.onTapPast,
    this.onClear,
  });

  /// null = show 2 buttons; non-null = show chip with formatted time.
  final DateTime? value;

  /// Opens a time-only picker for today.
  final VoidCallback onTapToday;

  /// Opens a date+time picker (past dates only).
  final VoidCallback onTapPast;

  /// Resets value to null (shows 2 buttons again). Only shown when
  /// [value] != null.
  final VoidCallback? onClear;

  String _format(DateTime t) {
    final now = DateTime.now();
    if (DateUtils.isSameDay(t, now)) {
      return DateFormat.jm().format(t); // "2:30 PM"
    }
    return DateFormat('EEE, ').format(t) + DateFormat.jm().format(t); // "Mon, 2:30 PM"
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    if (value == null) {
      // State 1: two buttons
      return Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onTapToday,
              icon: const Icon(Icons.schedule_outlined, size: 16),
              label: Text(l10n.loggedAtToday),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onTapPast,
              icon: const Icon(Icons.calendar_today_outlined, size: 16),
              label: Text(l10n.loggedAtPastDate),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // State 2: single chip
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_outlined, size: 16, color: scheme.primary),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            _format(value!),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          if (onClear != null) ...[
            const SizedBox(width: AppSpacing.xxs),
            GestureDetector(
              onTap: onClear,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xxs),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Opens a time-only picker for today.
///
/// Returns a [DateTime] on today at the picked time, or null if cancelled.
/// If the user accidentally scrolls the picker to a future minute, the result
/// is capped to [DateTime.now()] rather than returning null — avoids a silent
/// no-op that forces the user to tap again.
Future<DateTime?> pickTodayTime(BuildContext context) async {
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.now(),
  );
  if (time == null) return null;
  final now = DateTime.now();
  final result = DateTime(now.year, now.month, now.day, time.hour, time.minute);
  // Cap to now instead of returning null — avoids silent no-op when user
  // accidentally scrolls picker forward by a minute.
  return result.isAfter(now) ? now : result;
}

/// Opens a date picker (yesterday and before) then a time picker.
///
/// Returns a [DateTime] or null if cancelled.
Future<DateTime?> pickPastDateTime(
  BuildContext context,
  DateTime? current,
) async {
  final now = DateTime.now();
  final yesterday = DateTime(now.year, now.month, now.day - 1);
  final initial = (current != null && current.isBefore(now)) ? current : yesterday;
  final date = await showDatePicker(
    context: context,
    initialDate: DateUtils.isSameDay(initial, now) ? yesterday : initial,
    firstDate: now.subtract(const Duration(days: 30)),
    lastDate: yesterday, // past dates only, not today
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}
