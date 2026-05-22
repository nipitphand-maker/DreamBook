import 'dart:async';

import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/core/widgets/logged_at_chip.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/sleep/data/sleep_repository.dart';
import 'package:dreambook/features/sleep/presentation/sleep_history_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dreambook/core/router/app_router.dart';
import 'package:go_router/go_router.dart';

const _kSleepStartedAt = 'sleep.activeStartedAt';
const _kSleepId = 'sleep.activeId';

class SleepTimerScreen extends ConsumerStatefulWidget {
  const SleepTimerScreen({super.key});

  @override
  ConsumerState<SleepTimerScreen> createState() => _SleepTimerScreenState();
}

class _SleepTimerScreenState extends ConsumerState<SleepTimerScreen> {
  // --- Active session state ---
  String? _activeSleepId;
  DateTime? _activeSleepStartedAt;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;

  // --- Idle form state ---
  SleepLocation _location = SleepLocation.crib;
  final _notesCtrl = TextEditingController();

  // --- Past-entry form state ---
  bool _isPastMode = false;
  DateTime? _pastStart;
  DateTime? _pastEnd;
  SleepLocation _pastLocation = SleepLocation.crib;
  final _pastNotesCtrl = TextEditingController();

  bool get _isActive => _activeSleepId != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadState());
  }

  void _loadState() {
    final prefs = ref.read(sharedPreferencesProvider);
    final startedAtStr = prefs.getString(_kSleepStartedAt);
    final sleepId = prefs.getString(_kSleepId);
    final babyId = ref.read(currentBabyIdProvider);

    if (startedAtStr != null && sleepId != null && babyId != null) {
      // Cross-check DB: prefs can be stale if another device ended the session.
      ref.read(sleepActiveProvider(babyId).future).then((active) {
        if (!mounted) return;
        if (active?.id == sleepId) {
          // DB confirms session is still open — restore timer from prefs start time.
          final startedAt = DateTime.parse(startedAtStr);
          setState(() {
            _activeSleepId = sleepId;
            _activeSleepStartedAt = startedAt;
            _elapsed = DateTime.now().difference(startedAt);
          });
          _startTicker();
        } else {
          // Session ended (remotely or after crash) — clear stale prefs.
          prefs.remove(_kSleepStartedAt);
          prefs.remove(_kSleepId);
          // Check DB for any other active session.
          if (active != null) {
            setState(() {
              _activeSleepId = active.id;
              _activeSleepStartedAt = active.startedAt;
              _elapsed = DateTime.now().difference(active.startedAt);
            });
            _startTicker();
          }
        }
      });
    } else if (babyId != null) {
      // No prefs — DB is authoritative.
      ref.read(sleepActiveProvider(babyId).future).then((active) {
        if (!mounted) return;
        if (active != null) {
          setState(() {
            _activeSleepId = active.id;
            _activeSleepStartedAt = active.startedAt;
            _elapsed = DateTime.now().difference(active.startedAt);
          });
          _startTicker();
        }
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _notesCtrl.dispose();
    _pastNotesCtrl.dispose();
    super.dispose();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _activeSleepStartedAt != null) {
        setState(() => _elapsed = DateTime.now().difference(_activeSleepStartedAt!));
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _onStart() async {
    if (_activeSleepId != null) return; // guard: prevent double-start
    final babyId = ref.read(currentBabyIdProvider);
    if (babyId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.errorNoBabyProfile)),
      );
      return;
    }
    final prefs = ref.read(sharedPreferencesProvider);
    final repo = ref.read(sleepRepositoryProvider);
    final now = DateTime.now();
    final note = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    try {
      final sleep = await repo.start(
        babyId: babyId,
        startedAt: now,
        location: _location,
        note: note,
      );
      await prefs.setString(_kSleepStartedAt, now.toIso8601String());
      await prefs.setString(_kSleepId, sleep.id);

      if (!mounted) return;
      setState(() {
        _activeSleepId = sleep.id;
        _activeSleepStartedAt = now;
        _elapsed = Duration.zero;
      });
      _startTicker();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.errorSaveFailed)),
        );
      }
    }
  }

  Future<void> _onWakeUp() async {
    final babyId = ref.read(currentBabyIdProvider);
    if (babyId == null || _activeSleepId == null) return;

    final prefs = ref.read(sharedPreferencesProvider);
    final repo = ref.read(sleepRepositoryProvider);
    final now = DateTime.now();

    final Sleep ended;
    try {
      ended = await repo.end(_activeSleepId!, babyId: babyId, endedAt: now);
    } catch (e, st) {
      // DB lock, sqlcipher key miss, FK constraint, disk full — without this
      // guard the throw bubbles to the framework, leaves prefs intact, and
      // shows a "ghost active session" on next launch while the user
      // believes their sleep was saved.
      debugPrint('[sleep] _onWakeUp failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.errorGeneric)),
      );
      return;
    }
    await prefs.remove(_kSleepStartedAt);
    await prefs.remove(_kSleepId);
    _ticker?.cancel();

    if (!mounted) return;
    final totalMin = ended.durationMin ?? _elapsed.inMinutes;
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          h > 0
              ? context.l10n.sleepSleptForHM(h, m)
              : context.l10n.sleepSleptForM(m),
        ),
      ),
    );
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  Future<void> _onSavePast() async {
    final l10n = context.l10n;
    final now = DateTime.now();
    final effectiveStart = _pastStart ?? now.subtract(const Duration(hours: 2));
    final effectiveEnd = _pastEnd ?? now;
    if (!effectiveEnd.isAfter(effectiveStart)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.sleepEndBeforeStart)),
      );
      return;
    }
    final babyId = ref.read(currentBabyIdProvider);
    if (babyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorNoBabyProfile)),
      );
      return;
    }
    final note = _pastNotesCtrl.text.trim().isEmpty ? null : _pastNotesCtrl.text.trim();
    try {
      await ref.read(sleepRepositoryProvider).insertPast(
        babyId: babyId,
        startedAt: effectiveStart,
        endedAt: effectiveEnd,
        location: _pastLocation,
        note: note,
      );
    } catch (e, st) {
      // Surface DB / FK errors instead of silently doing nothing — the user
      // tapped Save and expects either a row written or an explanation.
      debugPrint('[sleep] _onSavePast failed: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.errorGeneric)),
      );
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.sleepPastSaved)),
    );
    setState(() {
      _isPastMode = false;
      _pastStart = null;
      _pastEnd = null;
      _pastNotesCtrl.clear();
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _fmtElapsed(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  String _fmtDuration(DateTime? start, DateTime? end) {
    if (start == null || end == null) return '--';
    final diff = end.difference(start);
    if (diff.isNegative) return '--';
    final h = diff.inHours;
    final m = diff.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    String title;
    if (_isActive) {
      title = l10n.sleepActiveTitle;
    } else if (_isPastMode) {
      title = l10n.sleepLogPast;
    } else {
      title = l10n.sleepTitle;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: _isPastMode
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _isPastMode = false),
              )
            : null,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.lg,
          ),
          child: _isActive
              ? _buildActiveBody(l10n)
              : _isPastMode
                  ? _buildPastBody(l10n)
                  : _buildIdleBody(l10n),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Idle body
  // ---------------------------------------------------------------------------

  Widget _buildIdleBody(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Icon(Icons.bedtime_outlined, size: 80, color: scheme.primary),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: Text(
            l10n.sleepTapStartHint,
            style: AppTypography.bodyMedium(color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SegmentedButton<SleepLocation>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: SleepLocation.crib, label: Text(l10n.sleepLocationCrib)),
            ButtonSegment(value: SleepLocation.stroller, label: Text(l10n.sleepLocationStroller)),
            ButtonSegment(value: SleepLocation.car, label: Text(l10n.sleepLocationCar)),
            ButtonSegment(value: SleepLocation.other, label: Text(l10n.sleepLocationOther)),
          ],
          selected: {_location},
          onSelectionChanged: (s) => setState(() => _location = s.first),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _notesCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: l10n.diaperNotesOptional,
            hintText: l10n.diaperNotesOptional,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: _onStart,
          child: Text(l10n.sleepStart),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextButton.icon(
          onPressed: () => setState(() {
            _isPastMode = true;
            _pastStart = null;
            _pastEnd = null;
            _pastLocation = SleepLocation.crib;
          }),
          icon: const Icon(Icons.history),
          label: Text(l10n.sleepLogPast),
        ),
        const SizedBox(height: AppSpacing.md),
        // --- Today's history ---
        Consumer(
          builder: (context, ref, _) {
            final babyId = ref.watch(currentBabyIdProvider);
            if (babyId == null) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Divider(),
                _SleepTodaySummary(babyId: babyId),
                SleepHistorySection(babyId: babyId),
              ],
            );
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Past entry body
  // ---------------------------------------------------------------------------

  Widget _buildPastBody(AppLocalizations l10n) {
    final effectiveStart = _pastStart;
    final effectiveEnd = _pastEnd;
    final durationText = _fmtDuration(effectiveStart, effectiveEnd);
    // Save requires an explicit start time; if end is set it must be after start.
    final bool canSave = effectiveStart != null &&
        (effectiveEnd == null || effectiveEnd.isAfter(effectiveStart));
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Start time
        Text(
          l10n.sleepFellAsleep,
          style: AppTypography.bodyMedium(
              color: scheme.onSurface.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: AppSpacing.xs),
        LoggedAtChip(
          value: _pastStart,
          onTapToday: () async {
            final picked = await pickTodayTime(context);
            if (picked != null && mounted) setState(() => _pastStart = picked);
          },
          onTapPast: () async {
            final picked = await pickPastDateTime(context, _pastStart);
            if (picked != null && mounted) setState(() => _pastStart = picked);
          },
          onClear: _pastStart != null
              ? () => setState(() => _pastStart = null)
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        // End time
        Text(
          l10n.sleepWokeUp,
          style: AppTypography.bodyMedium(
              color: scheme.onSurface.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: AppSpacing.xs),
        LoggedAtChip(
          value: _pastEnd,
          onTapToday: () async {
            final picked = await pickTodayTime(context);
            if (picked != null && mounted) setState(() => _pastEnd = picked);
          },
          onTapPast: () async {
            final picked = await pickPastDateTime(context, _pastEnd);
            if (picked != null && mounted) setState(() => _pastEnd = picked);
          },
          onClear: _pastEnd != null
              ? () => setState(() => _pastEnd = null)
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        // Duration (read-only)
        Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm,
            horizontal: AppSpacing.xs,
          ),
          child: Builder(builder: (ctx) {
            final cs = Theme.of(ctx).colorScheme;
            final isValid = effectiveStart != null &&
                effectiveEnd != null &&
                effectiveEnd.isAfter(effectiveStart);
            return Row(
              children: [
                Text(l10n.sleepDuration,
                    style: AppTypography.bodyMedium(color: cs.onSurface.withValues(alpha: 0.6))),
                const Spacer(),
                Text(
                  durationText,
                  style: AppTypography.numeric(
                    size: 16,
                    color: isValid ? cs.primary : cs.error,
                  ),
                ),
              ],
            );
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        // Location
        SegmentedButton<SleepLocation>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(value: SleepLocation.crib, label: Text(l10n.sleepLocationCrib)),
            ButtonSegment(value: SleepLocation.stroller, label: Text(l10n.sleepLocationStroller)),
            ButtonSegment(value: SleepLocation.car, label: Text(l10n.sleepLocationCar)),
            ButtonSegment(value: SleepLocation.other, label: Text(l10n.sleepLocationOther)),
          ],
          selected: {_pastLocation},
          onSelectionChanged: (s) => setState(() => _pastLocation = s.first),
        ),
        const SizedBox(height: AppSpacing.md),
        // Notes
        TextField(
          controller: _pastNotesCtrl,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: l10n.diaperNotesOptional,
            hintText: l10n.diaperNotesOptional,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(
          onPressed: canSave ? _onSavePast : null,
          child: Text(l10n.actionSave),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Active body
  // ---------------------------------------------------------------------------

  Widget _buildActiveBody(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            _fmtElapsed(_elapsed),
            style: AppTypography.statHero(color: scheme.onSurface),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: Text(
            l10n.sleepBabyIsSleeping,
            style: AppTypography.bodyLarge(color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
        ),
        if (_activeSleepStartedAt != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: Text(
              l10n.sleepStartedAtTime(
                '${_activeSleepStartedAt!.hour.toString().padLeft(2, '0')}:${_activeSleepStartedAt!.minute.toString().padLeft(2, '0')}',
              ),
              style: AppTypography.bodyMedium(color: scheme.onSurface.withValues(alpha: 0.6)),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppColors.lightSuccess),
          onPressed: _onWakeUp,
          child: Text(l10n.sleepWakeUp),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Today summary bar
// ---------------------------------------------------------------------------

class _SleepTodaySummary extends ConsumerWidget {
  const _SleepTodaySummary({required this.babyId});
  final String babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return ref.watch(sleepTodayProvider(babyId)).when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (sessions) {
        final completed = sessions.where((s) => s.endedAt != null).toList();
        final String detail;
        if (completed.isEmpty) {
          detail = l10n.todayNoSleepYet;
        } else {
          final totalMin = completed.fold<int>(
            0,
            (sum, s) => sum + (s.durationMin ?? 0),
          );
          final h = totalMin ~/ 60;
          final m = totalMin % 60;
          final duration = h > 0 ? '$h h $m m' : '$m m';
          detail = '${completed.length} ${completed.length == 1 ? 'session' : 'sessions'} · $duration';
        }

        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${l10n.todaySummaryPrefix}$detail',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        );
      },
    );
  }
}
