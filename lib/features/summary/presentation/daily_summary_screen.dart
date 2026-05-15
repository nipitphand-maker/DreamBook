import 'dart:async';

import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/core/router/app_router.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/core/widgets/premium_gate.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/feed/data/feed_repository.dart' show feedTodayProvider;
import 'package:dreambook/features/summary/data/daily_note_repository.dart';
import 'package:dreambook/features/summary/data/summary_provider.dart';
import 'package:dreambook/features/summary/presentation/feed_sparkline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class DailySummaryScreen extends ConsumerStatefulWidget {
  const DailySummaryScreen({super.key});

  @override
  ConsumerState<DailySummaryScreen> createState() =>
      _DailySummaryScreenState();
}

class _DailySummaryScreenState extends ConsumerState<DailySummaryScreen> {
  DateTime _selectedDate = _dateOnly(DateTime.now());

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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final babyId = ref.watch(currentBabyIdProvider);
    final isToday = _isToday;
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final dateLabel = isToday
        ? l10n.summaryToday
        : DateFormat('EEE, MMM d, yyyy').format(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _prevDay,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            GestureDetector(
              onTap: _pickDate,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Text(dateLabel),
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.chevron_right,
                color: isToday ? AppColors.inkSecondary : null,
              ),
              onPressed: isToday ? null : _nextDay,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
      body: babyId == null
          ? const _NoBabyPlaceholder()
          : _SummaryBody(
              babyId: babyId,
              dateStr: dateStr,
              isToday: isToday,
            ),
    );
  }
}

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
                value: summary.feedFormatted,
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
                  value: summary.stashFormatted,
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

// ── Daily note ─────────────────────────────────────────────────────────────

class _DailyNoteField extends ConsumerStatefulWidget {
  const _DailyNoteField({required this.babyId, required this.dateStr});

  final String babyId;
  final String dateStr;

  @override
  ConsumerState<_DailyNoteField> createState() => _DailyNoteFieldState();
}

class _DailyNoteFieldState extends ConsumerState<_DailyNoteField> {
  late TextEditingController _controller;
  Timer? _debounce;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
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
    final familyId = prefs.getString('family.id') ?? '';

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
            onChanged: (v) => _onChanged(v, familyId, 1),
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
