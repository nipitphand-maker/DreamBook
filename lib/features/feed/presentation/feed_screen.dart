import 'dart:async';

import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/feed/data/feed_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  bool _timerRunning = false;

  // Bottle state
  double _oz = 4.0;
  FeedSource _source = FeedSource.breastmilk;
  // ignore: unused_field
  // TODO(planB4): wire `_fromStash` to feed.from_stash_bottle_id when Stash
  // is introduced in B4.6. Currently a UI placeholder.
  bool _fromStash = false;

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
    _notesCtrl.dispose();
    super.dispose();
  }

  void _toggleTimer() {
    setState(() {
      if (_timerRunning) {
        _timerRunning = false;
      } else {
        _timerStarted = DateTime.now();
        _timerRunning = true;
        _elapsed = Duration.zero;
        unawaited(_tickTimer());
      }
    });
  }

  Future<void> _tickTimer() async {
    while (_timerRunning && mounted) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (_timerRunning && mounted && _timerStarted != null) {
        setState(() {
          _elapsed = DateTime.now().difference(_timerStarted!);
        });
      }
    }
  }

  Future<void> _save() async {
    final babyId = ref.read(currentBabyIdProvider);
    if (babyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No baby selected')),
      );
      return;
    }

    final repo = ref.read(feedRepositoryProvider);
    final startedAt = _timerStarted ?? DateTime.now();
    final endedAt = _timerRunning
        ? null
        : (_timerStarted != null ? DateTime.now() : null);
    final note = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    if (_tab == _Tab.breast) {
      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setString(_kLastSideKey, _side.name);
      await repo.insert(
        babyId: babyId,
        type: FeedType.breast,
        side: _side,
        startedAt: startedAt,
        endedAt: endedAt,
        note: note,
      );
    } else {
      await repo.insert(
        babyId: babyId,
        type: FeedType.bottle,
        oz: _oz,
        source: _source,
        startedAt: startedAt,
        endedAt: DateTime.now(),
        note: note,
      );
    }

    unawaited(HapticFeedback.lightImpact());
    if (!mounted) return;
    context.pop();
  }

  String _fmtElapsed() {
    final m = _elapsed.inMinutes.toString().padLeft(1, '0');
    final s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

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
                segments: const [
                  ButtonSegment(
                    value: _Tab.breast,
                    label: Text('Breast'),
                    icon: Icon(Icons.child_care_outlined),
                  ),
                  ButtonSegment(
                    value: _Tab.bottle,
                    label: Text('Bottle'),
                    icon: Icon(Icons.local_drink_outlined),
                  ),
                ],
                selected: {_tab},
                onSelectionChanged: (s) => setState(() => _tab = s.first),
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: _tab == _Tab.breast
                    ? _BreastForm(
                        side: _side,
                        onSideChanged: (s) => setState(() => _side = s),
                        timerRunning: _timerRunning,
                        elapsed: _fmtElapsed(),
                        onToggleTimer: _toggleTimer,
                      )
                    : _BottleForm(
                        oz: _oz,
                        onOzChanged: (v) => setState(() => _oz = v),
                        source: _source,
                        onSourceChanged: (s) => setState(() => _source = s),
                        fromStash: _fromStash,
                        onFromStashChanged: (v) =>
                            setState(() => _fromStash = v),
                      ),
              ),
              const SizedBox(height: AppSpacing.md),
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
            ],
          ),
        ),
      ),
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
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ChoiceChip(
              label: Text(l10n.feedSideLeft),
              selected: side == FeedSide.left,
              onSelected: (_) => onSideChanged(FeedSide.left),
            ),
            ChoiceChip(
              label: Text(l10n.feedSideRight),
              selected: side == FeedSide.right,
              onSelected: (_) => onSideChanged(FeedSide.right),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          elapsed,
          style: AppTypography.statHero(color: AppColors.inkPrimary),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(
          onPressed: onToggleTimer,
          icon: Icon(timerRunning ? Icons.pause : Icons.play_arrow),
          label: Text(timerRunning ? 'Pause' : 'Start'),
        ),
      ],
    );
  }
}

class _BottleForm extends StatelessWidget {
  const _BottleForm({
    required this.oz,
    required this.onOzChanged,
    required this.source,
    required this.onSourceChanged,
    required this.fromStash,
    required this.onFromStashChanged,
  });
  final double oz;
  final ValueChanged<double> onOzChanged;
  final FeedSource source;
  final ValueChanged<FeedSource> onSourceChanged;
  final bool fromStash;
  final ValueChanged<bool> onFromStashChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filled(
              onPressed: oz <= 0.5 ? null : () => onOzChanged(oz - 0.5),
              icon: const Icon(Icons.remove),
            ),
            const SizedBox(width: AppSpacing.lg),
            Text(
              '${oz.toStringAsFixed(1)} oz',
              style: AppTypography.statHero(color: AppColors.inkPrimary),
            ),
            const SizedBox(width: AppSpacing.lg),
            IconButton.filled(
              onPressed: oz >= 12 ? null : () => onOzChanged(oz + 0.5),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ChoiceChip(
              label: Text(l10n.feedSourceBreastmilk),
              selected: source == FeedSource.breastmilk,
              onSelected: (_) => onSourceChanged(FeedSource.breastmilk),
            ),
            ChoiceChip(
              label: Text(l10n.feedSourceFormula),
              selected: source == FeedSource.formula,
              onSelected: (_) => onSourceChanged(FeedSource.formula),
            ),
          ],
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
