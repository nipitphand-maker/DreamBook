import 'dart:async';

import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/sleep/data/sleep_repository.dart';
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
  DateTime _pastStart = DateTime.now().subtract(const Duration(hours: 2));
  DateTime _pastEnd = DateTime.now();
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

    if (startedAtStr != null && sleepId != null) {
      final startedAt = DateTime.parse(startedAtStr);
      setState(() {
        _activeSleepId = sleepId;
        _activeSleepStartedAt = startedAt;
        _elapsed = DateTime.now().difference(startedAt);
      });
      _startTicker();
    } else {
      final babyId = ref.read(currentBabyIdProvider);
      if (babyId == null) return;
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
  }

  Future<void> _onWakeUp() async {
    final babyId = ref.read(currentBabyIdProvider);
    if (babyId == null || _activeSleepId == null) return;

    final prefs = ref.read(sharedPreferencesProvider);
    final repo = ref.read(sleepRepositoryProvider);
    final now = DateTime.now();

    final ended = await repo.end(_activeSleepId!, babyId: babyId, endedAt: now);
    await prefs.remove(_kSleepStartedAt);
    await prefs.remove(_kSleepId);
    _ticker?.cancel();

    if (!mounted) return;
    final totalMin = ended.durationMin ?? _elapsed.inMinutes;
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(h > 0 ? 'Slept for ${h}h ${m}m' : 'Slept for ${m}m')),
    );
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  Future<void> _onSavePast() async {
    final l10n = context.l10n;
    if (!_pastEnd.isAfter(_pastStart)) {
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
    await ref.read(sleepRepositoryProvider).insertPast(
      babyId: babyId,
      startedAt: _pastStart,
      endedAt: _pastEnd,
      location: _pastLocation,
      note: note,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.sleepPastSaved)),
    );
    setState(() {
      _isPastMode = false;
      _pastNotesCtrl.clear();
    });
  }

  // ---------------------------------------------------------------------------
  // Time picker helpers
  // ---------------------------------------------------------------------------

  Future<void> _pickDateTime({
    required DateTime current,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null) return;
    onPicked(DateTime(date.year, date.month, date.day, time.hour, time.minute));
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

  String _fmtDateTime(DateTime dt) {
    final date = '${dt.day}/${dt.month}/${dt.year}';
    final time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return '$date  $time';
  }

  String _fmtDuration(DateTime start, DateTime end) {
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
      title = 'Sleeping... 💤';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(
          child: Icon(Icons.bedtime_outlined, size: 80, color: AppColors.lavender700),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: Text(
            'Tap Start to begin tracking',
            style: AppTypography.bodyMedium(color: AppColors.inkSecondary),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SegmentedButton<SleepLocation>(
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
            _pastStart = DateTime.now().subtract(const Duration(hours: 2));
            _pastEnd = DateTime.now();
            _pastLocation = SleepLocation.crib;
          }),
          icon: const Icon(Icons.history),
          label: Text(l10n.sleepLogPast),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Past entry body
  // ---------------------------------------------------------------------------

  Widget _buildPastBody(AppLocalizations l10n) {
    final durationText = _fmtDuration(_pastStart, _pastEnd);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Start time
        _TimeRow(
          label: l10n.sleepFellAsleep,
          value: _fmtDateTime(_pastStart),
          onTap: () => _pickDateTime(
            current: _pastStart,
            onPicked: (dt) => setState(() => _pastStart = dt),
          ),
        ),
        const Divider(height: 1),
        // End time
        _TimeRow(
          label: l10n.sleepWokeUp,
          value: _fmtDateTime(_pastEnd),
          onTap: () => _pickDateTime(
            current: _pastEnd,
            onPicked: (dt) => setState(() => _pastEnd = dt),
          ),
        ),
        const Divider(height: 1),
        // Duration (read-only)
        Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.sm,
            horizontal: AppSpacing.xs,
          ),
          child: Row(
            children: [
              Text(l10n.sleepDuration,
                  style: AppTypography.bodyMedium(color: AppColors.inkSecondary)),
              const Spacer(),
              Text(
                durationText,
                style: AppTypography.numeric(
                  size: 16,
                  color: _pastEnd.isAfter(_pastStart)
                      ? AppColors.lavender700
                      : AppColors.peach700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // Location
        SegmentedButton<SleepLocation>(
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
          onPressed: _onSavePast,
          child: Text(l10n.actionSave),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Active body
  // ---------------------------------------------------------------------------

  Widget _buildActiveBody(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            _fmtElapsed(_elapsed),
            style: AppTypography.statHero(color: AppColors.inkPrimary),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: Text(
            'Baby is sleeping',
            style: AppTypography.bodyLarge(color: AppColors.inkSecondary),
          ),
        ),
        if (_activeSleepStartedAt != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: Text(
              'Started at ${_activeSleepStartedAt!.hour.toString().padLeft(2, '0')}:${_activeSleepStartedAt!.minute.toString().padLeft(2, '0')}',
              style: AppTypography.bodyMedium(color: AppColors.inkSecondary),
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
// Time row widget
// ---------------------------------------------------------------------------

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.label,
    required this.value,
    required this.onTap,
  });
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
          horizontal: AppSpacing.xs,
        ),
        child: Row(
          children: [
            Text(label,
                style: AppTypography.bodyMedium(color: AppColors.inkSecondary)),
            const Spacer(),
            Text(
              value,
              style: AppTypography.numeric(size: 14, color: AppColors.inkPrimary),
            ),
            const SizedBox(width: AppSpacing.xs),
            const Icon(Icons.edit_outlined, size: 16, color: AppColors.inkSecondary),
          ],
        ),
      ),
    );
  }
}
