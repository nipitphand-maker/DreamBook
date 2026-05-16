import 'dart:async';

import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/core/providers/unit_preferences_provider.dart';
import 'package:dreambook/core/router/app_router.dart';
import 'package:dreambook/core/sync/sync_constants.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/core/widgets/premium_gate.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/feed/data/feed_repository.dart' show feedTodayProvider;
import 'package:dreambook/core/crypto/family_key_service.dart';
import 'package:dreambook/features/summary/data/daily_note_repository.dart';
import 'package:dreambook/features/summary/data/summary_provider.dart';
import 'package:dreambook/features/summary/presentation/feed_sparkline.dart';
import 'package:dreambook/features/summary/presentation/history_calendar_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

// ── Period enum ─────────────────────────────────────────────────────────────

enum SummaryPeriod { today, week, month, custom }

// ── Screen ──────────────────────────────────────────────────────────────────

class DailySummaryScreen extends ConsumerStatefulWidget {
  const DailySummaryScreen({super.key});

  @override
  ConsumerState<DailySummaryScreen> createState() =>
      _DailySummaryScreenState();
}

class _DailySummaryScreenState extends ConsumerState<DailySummaryScreen> {
  DateTime _selectedDate = _dateOnly(DateTime.now());

  SummaryPeriod _period = SummaryPeriod.today;
  DateTime? _customFrom;
  DateTime? _customTo;

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool get _isToday {
    final t = _dateOnly(DateTime.now());
    return _selectedDate == t;
  }

  void _prevDay() =>
      setState(() => _selectedDate = _selectedDate.subtract(const Duration(days: 1)));

  void _nextDay() {
    if (_isToday) return;
    setState(() => _selectedDate = _selectedDate.add(const Duration(days: 1)));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: _dateOnly(DateTime.now()),
    );
    if (picked != null) setState(() => _selectedDate = _dateOnly(picked));
  }

  Future<void> _showHistoryCalendar() async {
    final babyId = ref.read(currentBabyIdProvider);
    if (babyId == null || !mounted) return;
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      builder: (_) => HistoryCalendarSheet(
        babyId: babyId,
        initialDate: _selectedDate,
        firstDate: DateTime(2020),
        lastDate: _dateOnly(DateTime.now()),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = _dateOnly(picked);
        _period = SummaryPeriod.today;
      });
    }
  }

  Future<void> _pickCustomRange() async {
    final now = _dateOnly(DateTime.now());
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _customFrom != null && _customTo != null
          ? DateTimeRange(start: _customFrom!, end: _customTo!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 6)),
              end: now,
            ),
    );
    if (result != null) {
      setState(() {
        _customFrom = _dateOnly(result.start);
        _customTo = _dateOnly(result.end);
        _period = SummaryPeriod.custom;
      });
    }
  }

  void _selectPeriod(SummaryPeriod p) {
    if (p == SummaryPeriod.custom) {
      _pickCustomRange();
      return;
    }
    setState(() => _period = p);
  }

  /// Computes the from/to range based on the current period.
  (DateTime, DateTime) get _rangeForPeriod {
    final now = _dateOnly(DateTime.now());
    return switch (_period) {
      SummaryPeriod.today => (now, now),
      SummaryPeriod.week =>
        (now.subtract(const Duration(days: 6)), now),
      SummaryPeriod.month =>
        (now.subtract(const Duration(days: 29)), now),
      SummaryPeriod.custom => (
          _customFrom ?? now.subtract(const Duration(days: 6)),
          _customTo ?? now,
        ),
    };
  }

  int get _rangeDayCount {
    final (from, to) = _rangeForPeriod;
    return to.difference(from).inDays + 1;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final babyId = ref.watch(currentBabyIdProvider);
    final isToday = _period == SummaryPeriod.today && _isToday;
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final dateLabel = _isToday
        ? l10n.summaryToday
        : DateFormat('EEE, MMM d, yyyy').format(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: _period == SummaryPeriod.today
            ? _DayNavigator(
                dateLabel: dateLabel,
                isToday: _isToday,
                onPrev: _prevDay,
                onNext: _nextDay,
                onPickDate: _pickDate,
              )
            : Text(l10n.summaryTitle),
        actions: [
          IconButton(
            key: const Key('summary_calendar_button'),
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: _showHistoryCalendar,
          ),
        ],
      ),
      body: babyId == null
          ? const _NoBabyPlaceholder()
          : Column(
              children: [
                _PeriodChips(
                  period: _period,
                  onSelect: _selectPeriod,
                ),
                Expanded(
                  child: _period == SummaryPeriod.today
                      ? _SummaryBody(
                          babyId: babyId,
                          dateStr: dateStr,
                          isToday: isToday,
                        )
                      : _RangeSummaryBody(
                          babyId: babyId,
                          from: _rangeForPeriod.$1,
                          to: _rangeForPeriod.$2,
                          dayCount: _rangeDayCount,
                          period: _period,
                          customFrom: _customFrom,
                          customTo: _customTo,
                        ),
                ),
              ],
            ),
    );
  }
}

// ── Period chip row ─────────────────────────────────────────────────────────

class _PeriodChips extends StatelessWidget {
  const _PeriodChips({required this.period, required this.onSelect});

  final SummaryPeriod period;
  final void Function(SummaryPeriod) onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          _Chip(
            label: l10n.summaryPeriodToday,
            selected: period == SummaryPeriod.today,
            onTap: () => onSelect(SummaryPeriod.today),
          ),
          const SizedBox(width: AppSpacing.xs),
          _Chip(
            label: l10n.summaryPeriodWeek,
            selected: period == SummaryPeriod.week,
            onTap: () => onSelect(SummaryPeriod.week),
          ),
          const SizedBox(width: AppSpacing.xs),
          _Chip(
            label: l10n.summaryPeriodMonth,
            selected: period == SummaryPeriod.month,
            onTap: () => onSelect(SummaryPeriod.month),
          ),
          const SizedBox(width: AppSpacing.xs),
          _Chip(
            label: '${l10n.summaryPeriodCustom} ↗',
            selected: period == SummaryPeriod.custom,
            onTap: () => onSelect(SummaryPeriod.custom),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      labelStyle: AppTypography.labelLarge(
        color: selected ? AppColors.inkPrimary : AppColors.inkSecondary,
      ),
    );
  }
}

// ── Day navigator (Today mode) ───────────────────────────────────────────────

class _DayNavigator extends StatelessWidget {
  const _DayNavigator({
    required this.dateLabel,
    required this.isToday,
    required this.onPrev,
    required this.onNext,
    required this.onPickDate,
  });

  final String dateLabel;
  final bool isToday;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onPickDate;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: onPrev,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        GestureDetector(
          onTap: onPickDate,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            child: Text(dateLabel),
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.chevron_right,
            color: isToday ? AppColors.inkSecondary : null,
          ),
          onPressed: isToday ? null : onNext,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
      ],
    );
  }
}

// ── No baby placeholder ──────────────────────────────────────────────────────

class _NoBabyPlaceholder extends StatelessWidget {
  const _NoBabyPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        context.l10n.summaryNoBabyProfile,
        style: AppTypography.bodyLarge(color: AppColors.inkSecondary),
      ),
    );
  }
}

// ── Single-day summary body ──────────────────────────────────────────────────

class _SummaryBody extends ConsumerWidget {
  const _SummaryBody({
    required this.babyId,
    required this.dateStr,
    required this.isToday,
  });

  final String babyId;
  final String dateStr;
  final bool isToday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final volumeUnit = ref.watch(unitPreferencesProvider).volume;
    final summaryAsync = isToday
        ? ref.watch(dailySummaryProvider(babyId))
        : ref.watch(dailySummaryForDateProvider((babyId, dateStr)));
    final feedListAsync = isToday
        ? ref.watch(feedTodayProvider(babyId))
        : ref.watch(feedForDateProvider((babyId, dateStr)));

    return summaryAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          l10n.summaryLoadError,
          style: AppTypography.bodyLarge(color: AppColors.inkSecondary),
        ),
      ),
      data: (summary) {
        final feeds = feedListAsync.value ?? const <Feed>[];
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Feeding
              _SummaryCard(
                icon: Icons.water_drop_outlined,
                label: l10n.summaryFeedingLabel,
                value: summary.feedFormatted(volumeUnit),
                color: AppColors.peach700,
              ),
              const SizedBox(height: AppSpacing.xs),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: FeedSparkline(feeds: feeds),
              ),
              const SizedBox(height: AppSpacing.md),

              // Pump
              _SummaryCard(
                icon: Icons.compress_outlined,
                label: l10n.summaryPumpLabel,
                value: '${summary.pumpCount} sessions',
                color: AppColors.peach700,
              ),
              const SizedBox(height: AppSpacing.md),

              // Diaper
              _SummaryCard(
                icon: Icons.baby_changing_station_outlined,
                label: l10n.summaryDiapersLabel,
                value: '${summary.diaperCount} changes',
                color: AppColors.honey700,
              ),
              const SizedBox(height: AppSpacing.md),

              // Sleep
              _SummaryCard(
                icon: Icons.bedtime_outlined,
                label: l10n.homeQuickLogSleep,
                value: summary.sleepFormatted +
                    (summary.babyIsAsleep
                        ? ' · ${l10n.summarySleepingNow}'
                        : ''),
                color: AppColors.sage700,
              ),
              const SizedBox(height: AppSpacing.md),

              // Stash (today only — historical stash not date-scoped)
              if (isToday)
                _SummaryCard(
                  icon: Icons.ac_unit,
                  label: l10n.stashTitle,
                  value: summary.stashFormatted(volumeUnit),
                  color: AppColors.inkSecondary,
                ),
              if (isToday) const SizedBox(height: AppSpacing.md),

              // Daily note
              _DailyNoteField(babyId: babyId, dateStr: dateStr),
              const SizedBox(height: AppSpacing.lg),

              // Visit PDF (premium — today only)
              if (isToday) _VisitPdfButton(babyId: babyId),
              if (isToday) const SizedBox(height: AppSpacing.lg),
            ],
          ),
        );
      },
    );
  }
}

// ── Range summary body ───────────────────────────────────────────────────────

class _RangeSummaryBody extends ConsumerWidget {
  const _RangeSummaryBody({
    required this.babyId,
    required this.from,
    required this.to,
    required this.dayCount,
    required this.period,
    this.customFrom,
    this.customTo,
  });

  final String babyId;
  final DateTime from;
  final DateTime to;
  final int dayCount;
  final SummaryPeriod period;
  final DateTime? customFrom;
  final DateTime? customTo;

  String _subtitle(BuildContext context) {
    final l10n = context.l10n;
    if (period == SummaryPeriod.custom &&
        customFrom != null &&
        customTo != null) {
      final fmt = DateFormat('MMM d');
      return l10n.summaryCustomRange(
        fmt.format(customFrom!),
        fmt.format(customTo!),
      );
    }
    return l10n.summaryRangeTotal(dayCount);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final volumeUnit = ref.watch(unitPreferencesProvider).volume;
    final summaryAsync =
        ref.watch(summaryForRangeProvider((babyId, from, to)));

    return summaryAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          l10n.summaryLoadError,
          style: AppTypography.bodyLarge(color: AppColors.inkSecondary),
        ),
      ),
      data: (summary) {
        final subtitle = _subtitle(context);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Range subtitle
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  subtitle,
                  style: AppTypography.labelLarge(
                      color: AppColors.inkSecondary),
                  textAlign: TextAlign.center,
                ),
              ),

              // Feeding
              _SummaryCard(
                icon: Icons.water_drop_outlined,
                label: l10n.summaryFeedingLabel,
                value: summary.feedFormatted(volumeUnit),
                color: AppColors.peach700,
              ),
              const SizedBox(height: AppSpacing.md),

              // Pump
              _SummaryCard(
                icon: Icons.compress_outlined,
                label: l10n.summaryPumpLabel,
                value: '${summary.pumpCount} sessions',
                color: AppColors.peach700,
              ),
              const SizedBox(height: AppSpacing.md),

              // Diaper
              _SummaryCard(
                icon: Icons.baby_changing_station_outlined,
                label: l10n.summaryDiapersLabel,
                value: '${summary.diaperCount} changes',
                color: AppColors.honey700,
              ),
              const SizedBox(height: AppSpacing.md),

              // Sleep
              _SummaryCard(
                icon: Icons.bedtime_outlined,
                label: l10n.homeQuickLogSleep,
                value: summary.sleepFormatted,
                color: AppColors.sage700,
              ),
              const SizedBox(height: AppSpacing.md),

              // Stash — current value, always shown in range view
              _SummaryCard(
                icon: Icons.ac_unit,
                label: l10n.summaryCurrentStash,
                value: summary.stashFormatted(volumeUnit),
                color: AppColors.inkSecondary,
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        );
      },
    );
  }
}

// ── Daily note ─────────────────────────────────────────────────────────────

class _DailyNoteField extends ConsumerStatefulWidget {
  const _DailyNoteField({required this.babyId, required this.dateStr});

  final String babyId;
  final String dateStr;

  @override
  ConsumerState<_DailyNoteField> createState() => _DailyNoteFieldState();
}

const _secureStorage = FlutterSecureStorage();

class _DailyNoteFieldState extends ConsumerState<_DailyNoteField> {
  late TextEditingController _controller;
  Timer? _debounce;
  bool _loaded = false;
  int _keyVersion = 1;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    // Load the current key version so notes are encrypted with the correct key.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final prefs = ref.read(sharedPreferencesProvider);
      final familyId = prefs.getString(kFamilyIdPrefsKey) ?? '';
      if (familyId.isNotEmpty) {
        FamilyKeyService(_secureStorage).read(familyId: familyId).then((key) {
          if (mounted && key != null) setState(() => _keyVersion = key.keyVersion);
        });
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value, String familyId, int keyVersion) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      ref.read(dailyNoteRepositoryProvider).upsert(
            babyId: widget.babyId,
            date: widget.dateStr,
            body: value,
            familyId: familyId,
            keyVersion: keyVersion,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final noteAsync =
        ref.watch(dailyNoteForDateProvider((widget.babyId, widget.dateStr)));
    final prefs = ref.read(sharedPreferencesProvider);
    final familyId = prefs.getString(kFamilyIdPrefsKey) ?? '';

    if (!_loaded && noteAsync is AsyncData) {
      final body = noteAsync.value?.body ?? '';
      if (_controller.text != body) {
        _controller.text = body;
        _controller.selection =
            TextSelection.collapsed(offset: _controller.text.length);
      }
      _loaded = true;
    }

    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.edit_note, size: 18, color: AppColors.inkSecondary),
            const SizedBox(width: AppSpacing.xs),
            Text(
              l10n.summaryNoteSection,
              style: AppTypography.labelLarge(color: AppColors.inkSecondary),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: TextField(
            controller: _controller,
            minLines: 3,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              hintText: l10n.summaryNoteHint,
              hintStyle:
                  AppTypography.bodyMedium(color: AppColors.inkSecondary),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(AppSpacing.md),
            ),
            onChanged: (v) => _onChanged(v, familyId, _keyVersion),
          ),
        ),
      ],
    );
  }
}

// ── Shared widgets ──────────────────────────────────────────────────────────

class _VisitPdfButton extends StatelessWidget {
  const _VisitPdfButton({required this.babyId});

  final String babyId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PremiumGate(
      lockedChild: FilledButton.icon(
        icon: const Icon(Icons.lock_outline),
        label: Text(l10n.summaryGeneratePdf),
        onPressed: () => context.push(AppRoutes.premium),
        style: FilledButton.styleFrom(backgroundColor: Colors.grey),
      ),
      child: FilledButton.icon(
        icon: const Icon(Icons.picture_as_pdf_outlined),
        label: Text(l10n.summaryGeneratePdf),
        onPressed: () => context.push(AppRoutes.visitReport),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style:
                      AppTypography.labelLarge(color: AppColors.inkSecondary),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  value,
                  style:
                      AppTypography.titleLarge(color: AppColors.inkPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
