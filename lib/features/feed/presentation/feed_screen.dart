import 'dart:async';

import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/core/providers/unit_preferences_provider.dart';
import 'package:dreambook/core/services/unit_preferences.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/core/widgets/logged_at_chip.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/feed/data/feed_repository.dart';
import 'package:dreambook/features/feed/presentation/feed_history_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dreambook/core/router/app_router.dart';
import 'package:go_router/go_router.dart';

/// Log a feed — either Breast (L/R + duration timer) or Bottle (oz stepper +
/// source). One-handed: primary CTAs live in the bottom thumb-zone so a
/// nursing parent can hit Save without shifting baby.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

enum _Tab { breast, bottle }

const _kLastSideKey = 'feed.lastSide';
// ignore: unused_element
const _kLastUnitKey = 'feed.lastUnit';
const _kNotesMaxLen = 240;

class _FeedScreenState extends ConsumerState<FeedScreen> {
  _Tab _tab = _Tab.breast;

  // Breast state
  FeedSide _side = FeedSide.left;
  DateTime? _timerStarted;
  Duration _elapsed = Duration.zero;
  Duration _pausedAccumulated = Duration.zero;
  bool _timerRunning = false;

  // Bottle state
  double _oz = 4.0;
  FeedSource _source = FeedSource.breastmilk;
  // ignore: unused_field
  // TODO(planB4): wire `_fromStash` to feed.from_stash_bottle_id when Stash
  // is introduced in B4.6. Currently a UI placeholder.
  bool _fromStash = false;

  // null = now; set when caregiver logs a past feed
  DateTime? _loggedAt;

  final _notesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(sharedPreferencesProvider);
    final lastSide = prefs.getString(_kLastSideKey);
    if (lastSide == 'right') _side = FeedSide.right;
    if (lastSide == 'both') _side = FeedSide.both;
  }

  @override
  void dispose() {
    _timerRunning = false;
    _notesCtrl.dispose();
    super.dispose();
  }

  void _toggleTimer() {
    setState(() {
      if (_timerRunning) {
        // Pause: accumulate the time elapsed since last resume.
        _pausedAccumulated += DateTime.now().difference(_timerStarted!);
        _timerStarted = null;
        _timerRunning = false;
      } else {
        // Resume (or first start): record a fresh start instant.
        _timerStarted = DateTime.now();
        _timerRunning = true;
        unawaited(_tickTimer());
      }
    });
  }

  Future<void> _tickTimer() async {
    while (_timerRunning && mounted) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (_timerRunning && mounted && _timerStarted != null) {
        setState(() {
          _elapsed = _pausedAccumulated + DateTime.now().difference(_timerStarted!);
        });
      }
    }
  }

  Future<void> _save() async {
    final babyId = ref.read(currentBabyIdProvider);
    if (babyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.errorNoBabyProfile)),
      );
      return;
    }

    // BUG-02: if the timer is still running when Save is tapped, stop it now
    // so we can record a valid endedAt.
    if (_timerRunning) {
      _pausedAccumulated += DateTime.now().difference(_timerStarted!);
      _timerStarted = null;
      _timerRunning = false;
    }

    final repo = ref.read(feedRepositoryProvider);
    final now = DateTime.now();
    final note = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    if (_tab == _Tab.breast) {
      // Anchor the session to the user-picked time (or now).
      // If a timer ran, shift the entire session so startedAt = anchor.
      final anchor = _loggedAt ?? (
        _pausedAccumulated > Duration.zero
            ? now.subtract(_pausedAccumulated)
            : now
      );
      final endedAt = _pausedAccumulated > Duration.zero
          ? anchor.add(_pausedAccumulated)
          : null;
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setString(_kLastSideKey, _side.name);
      await repo.insert(
        babyId: babyId,
        type: FeedType.breast,
        side: _side,
        startedAt: anchor,
        endedAt: endedAt,
        note: note,
      );
    } else {
      await repo.insert(
        babyId: babyId,
        type: FeedType.bottle,
        oz: _oz,
        source: _source,
        startedAt: _loggedAt ?? now,
        endedAt: null,
        note: note,
      );
    }

    unawaited(HapticFeedback.lightImpact());
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  Future<void> _pickToday() async {
    final picked = await pickTodayTime(context);
    if (picked != null && mounted) setState(() => _loggedAt = picked);
  }

  Future<void> _pickPast() async {
    final picked = await pickPastDateTime(context, _loggedAt);
    if (picked != null && mounted) setState(() => _loggedAt = picked);
  }

  String _fmtElapsed() {
    final m = _elapsed.inMinutes.toString().padLeft(1, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final unit = ref.watch(unitPreferencesProvider).volume;

    final babyId = ref.watch(currentBabyIdProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.feedScreenTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<_Tab>(
                segments: [
                  ButtonSegment(
                    value: _Tab.breast,
                    label: Text(l10n.feedTypeBreast),
                    icon: const Icon(Icons.child_care_outlined),
                  ),
                  ButtonSegment(
                    value: _Tab.bottle,
                    label: Text(l10n.feedTypeBottle),
                    icon: const Icon(Icons.local_drink_outlined),
                  ),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _tab == _Tab.breast
                          ? _BreastForm(
                              side: _side,
                              onSideChanged: (s) => setState(() => _side = s),
                              timerRunning: _timerRunning,
                              elapsed: _fmtElapsed(),
                              onToggleTimer: _toggleTimer,
                            )
                          : _BottleForm(
                              oz: _oz,
                              unit: unit,
                              onOzChanged: (v) => setState(() => _oz = v),
                              source: _source,
                              onSourceChanged: (s) => setState(() => _source = s),
                              fromStash: _fromStash,
                              onFromStashChanged: (v) =>
                                  setState(() => _fromStash = v),
                            ),
                      const SizedBox(height: AppSpacing.md),
                      LoggedAtChip(
                        value: _loggedAt,
                        onTapToday: _pickToday,
                        onTapPast: _pickPast,
                        onClear: _loggedAt != null
                            ? () => setState(() => _loggedAt = null)
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _notesCtrl,
                        maxLength: _kNotesMaxLen,
                        maxLines: 2,
                        decoration: InputDecoration(labelText: l10n.feedNotes),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton(
                        onPressed: _save,
                        child: Text(l10n.actionSave),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (babyId != null) ...[
                        const Divider(),
                        _FeedTodaySummary(babyId: babyId),
                        FeedHistorySection(babyId: babyId),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Today summary bar
// ---------------------------------------------------------------------------

class _FeedTodaySummary extends ConsumerWidget {
  const _FeedTodaySummary({required this.babyId});
  final String babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return ref.watch(feedTodayProvider(babyId)).when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (feeds) {
        final breastCount = feeds.where((f) => f.type == FeedType.breast).length;
        final bottleFeeds = feeds.where((f) => f.type == FeedType.bottle).toList();
        final bottleCount = bottleFeeds.length;
        final bottleOz = bottleFeeds
            .where((f) => f.oz != null)
            .fold<double>(0.0, (sum, f) => sum + f.oz!);

        final String detail;
        if (feeds.isEmpty) {
          detail = l10n.todayNoFeedsYet;
        } else {
          final parts = <String>[];
          if (breastCount > 0) {
            final breastLabel = breastCount == 1 ? '1 breast feed' : '$breastCount breast feeds';
            parts.add(breastLabel);
          }
          if (bottleCount > 0) {
            final ozStr = bottleOz > 0 ? '${bottleOz.toStringAsFixed(1)} oz' : '—';
            parts.add('$ozStr bottle');
          }
          detail = parts.isEmpty ? l10n.todayNoFeedsYet : parts.join(' · ');
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

class _BreastForm extends StatelessWidget {
  const _BreastForm({
    required this.side,
    required this.onSideChanged,
    required this.timerRunning,
    required this.elapsed,
    required this.onToggleTimer,
  });
  final FeedSide side;
  final ValueChanged<FeedSide> onSideChanged;
  final bool timerRunning;
  final String elapsed;
  final VoidCallback onToggleTimer;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<FeedSide>(
          segments: [
            ButtonSegment(value: FeedSide.left, label: Text(l10n.feedSideLeft)),
            ButtonSegment(value: FeedSide.right, label: Text(l10n.feedSideRight)),
          ],
          selected: {side},
          onSelectionChanged: (s) => onSideChanged(s.first),
          showSelectedIcon: false,
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          elapsed,
          textAlign: TextAlign.center,
          style: AppTypography.statHero(color: AppColors.inkPrimary),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: onToggleTimer,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
          ),
          icon: Icon(timerRunning ? Icons.pause_circle_outlined : Icons.play_circle_outlined),
          label: Text(timerRunning ? l10n.feedTimerPause : l10n.feedTimerStart),
        ),
      ],
    );
  }
}

class _BottleForm extends StatelessWidget {
  const _BottleForm({
    required this.oz,
    required this.unit,
    required this.onOzChanged,
    required this.source,
    required this.onSourceChanged,
    required this.fromStash,
    required this.onFromStashChanged,
  });
  final double oz; // always in oz internally
  final VolumeUnit unit;
  final ValueChanged<double> onOzChanged;
  final FeedSource source;
  final ValueChanged<FeedSource> onSourceChanged;
  final bool fromStash;
  final ValueChanged<bool> onFromStashChanged;

  static const _mlPerOz = 29.5735;
  static double _step(VolumeUnit u) => u == VolumeUnit.oz ? 0.5 : 5.0 / _mlPerOz;
  static double _max(VolumeUnit u) => u == VolumeUnit.oz ? 12.0 : 360.0 / _mlPerOz;

  String _fmtOz() => unit == VolumeUnit.oz
      ? '${oz.toStringAsFixed(1)} oz'
      : '${(oz * _mlPerOz).round()} ml';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final step = _step(unit);
    final max = _max(unit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filled(
              onPressed: oz <= 0.0 ? null : () => onOzChanged(
                double.parse((oz - step).clamp(0.0, max).toStringAsFixed(5)),
              ),
              icon: const Icon(Icons.remove),
            ),
            const SizedBox(width: AppSpacing.lg),
            Text(
              _fmtOz(),
              style: AppTypography.statHero(color: AppColors.inkPrimary),
            ),
            const SizedBox(width: AppSpacing.lg),
            IconButton.filled(
              onPressed: oz >= max ? null : () => onOzChanged(
                double.parse((oz + step).clamp(0.0, max).toStringAsFixed(5)),
              ),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SegmentedButton<FeedSource>(
          segments: [
            ButtonSegment(
              value: FeedSource.breastmilk,
              label: Text(l10n.feedSourceBreastmilk),
            ),
            ButtonSegment(
              value: FeedSource.formula,
              label: Text(l10n.feedSourceFormula),
            ),
          ],
          selected: {source},
          onSelectionChanged: (s) => onSourceChanged(s.first),
          showSelectedIcon: false,
        ),
        const SizedBox(height: AppSpacing.md),
        CheckboxListTile(
          value: fromStash,
          onChanged: (v) => onFromStashChanged(v ?? false),
          title: Text(l10n.feedFromFreezerStash),
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }
}

