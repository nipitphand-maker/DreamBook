import 'dart:async';

import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/core/providers/unit_preferences_provider.dart';
import 'package:dreambook/core/services/unit_preferences.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/widgets/logged_at_chip.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/pump/data/pump_repository.dart';
import 'package:dreambook/features/pump/presentation/pump_history_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dreambook/core/router/app_router.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// SharedPreferences keys
// ---------------------------------------------------------------------------

const _kTimerStartedAt = 'pump.timerStartedAt'; // ISO-8601 string
const _kTimerPausedAt = 'pump.timerPausedAt'; // ISO-8601 string
const _kPausedDurSec = 'pump.timerPausedDurSec'; // int
const _kTimerStopped = 'pump.timerStopped'; // bool — true when user tapped Stop
const _kSaveToStash = 'pump.saveToStash'; // bool
const _kStashStorage = 'pump.stashStorage'; // StorageType.name
const _kSide = 'pump.side'; // 'both'|'left'|'right'
const _kPortionOz = 'settings.pump.portionOz'; // double, default 4.0

// ---------------------------------------------------------------------------
// Side enum
// ---------------------------------------------------------------------------

enum _Side { both, left, right }

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Record a pump session — timer, L/R oz inputs, side toggle, stash opt-in.
/// State is persisted to SharedPreferences so a background kill mid-session
/// can be recovered on re-open.
class PumpSessionScreen extends ConsumerStatefulWidget {
  const PumpSessionScreen({super.key});

  @override
  ConsumerState<PumpSessionScreen> createState() => _PumpSessionScreenState();
}

class _PumpSessionScreenState extends ConsumerState<PumpSessionScreen> {
  // --- UI state ---
  _Side _side = _Side.both;
  bool _saveToStash = true;
  StorageType _stashStorage = StorageType.freezer;
  final _notesCtrl = TextEditingController();

  // --- Timer state ---
  DateTime? _timerStartedAt;
  DateTime? _timerPausedAt;
  int _pausedTotalSec = 0;
  bool _timerRunning = false;
  bool _timerStartedEver = false;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;

  // --- Oz state ---
  double _leftOz = 0;
  double _rightOz = 0;

  // --- Bottle splitting state ---
  double _portionOz = 4.0;
  List<double> _bottles = [];

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _loadPersistedState();
  }

  void _loadPersistedState() {
    final prefs = ref.read(sharedPreferencesProvider);

    // Restore side preference
    final side = prefs.getString(_kSide);
    if (side == 'left') _side = _Side.left;
    if (side == 'right') _side = _Side.right;

    // Restore stash preference
    _saveToStash = prefs.getBool(_kSaveToStash) ?? true;
    _stashStorage = StorageType.values.firstWhere(
      (e) => e.name == (prefs.getString(_kStashStorage) ?? 'freezer'),
      orElse: () => StorageType.freezer,
    );

    // Restore portion oz preference
    _portionOz = prefs.getDouble(_kPortionOz) ?? 4.0;
    _bottles = _computeBottles();

    // Recover in-progress timer
    final startedAtStr = prefs.getString(_kTimerStartedAt);
    if (startedAtStr != null) {
      _timerStartedAt = DateTime.parse(startedAtStr);
      _timerStartedEver = true;
      _pausedTotalSec = prefs.getInt(_kPausedDurSec) ?? 0;

      final wasStopped = prefs.getBool(_kTimerStopped) ?? false;
      final pausedAtStr = prefs.getString(_kTimerPausedAt);

      if (wasStopped) {
        // User tapped Stop — restore as stopped (elapsed locked, no ticker).
        _timerRunning = false;
        _elapsed = DateTime.now().difference(_timerStartedAt!) -
            Duration(seconds: _pausedTotalSec);
      } else if (pausedAtStr != null) {
        // App was killed mid-pause — restore paused state.
        _timerPausedAt = DateTime.parse(pausedAtStr);
        _timerRunning = false;
        _elapsed = _timerPausedAt!.difference(_timerStartedAt!) -
            Duration(seconds: _pausedTotalSec);
      } else {
        // Timer was running when app was killed — resume.
        _timerRunning = true;
        _elapsed = DateTime.now().difference(_timerStartedAt!) -
            Duration(seconds: _pausedTotalSec);
        _startTicker();
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Timer
  // ---------------------------------------------------------------------------

  Duration get _currentElapsed {
    if (_timerStartedAt == null) return Duration.zero;
    return DateTime.now().difference(_timerStartedAt!) -
        Duration(seconds: _pausedTotalSec);
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _elapsed = _currentElapsed;
        });
      }
    });
  }

  Future<void> _onStart() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final now = DateTime.now();
    setState(() {
      _timerStartedAt = now;
      _timerStartedEver = true;
      _timerRunning = true;
      _pausedTotalSec = 0;
      _elapsed = Duration.zero;
    });
    await prefs.setString(_kTimerStartedAt, now.toIso8601String());
    await prefs.remove(_kTimerPausedAt);
    await prefs.setInt(_kPausedDurSec, 0);
    _startTicker();
  }

  Future<void> _onPause() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final now = DateTime.now();
    _ticker?.cancel();
    setState(() {
      _timerPausedAt = now;
      _timerRunning = false;
      _elapsed = _currentElapsed;
    });
    await prefs.setString(_kTimerPausedAt, now.toIso8601String());
  }

  Future<void> _onStop() async {
    final prefs = ref.read(sharedPreferencesProvider);
    _ticker?.cancel();
    setState(() {
      _elapsed = _currentElapsed;
      _timerRunning = false;
    });
    // Mark stopped so a kill+restore shows stopped state, not running.
    await prefs.setBool(_kTimerStopped, true);
    await prefs.remove(_kTimerPausedAt);
  }

  Future<void> _onResume() async {
    if (_timerStartedAt == null) return;
    final prefs = ref.read(sharedPreferencesProvider);
    // Accumulate time that was spent paused
    if (_timerPausedAt != null) {
      final extraPaused =
          DateTime.now().difference(_timerPausedAt!).inSeconds;
      setState(() {
        _pausedTotalSec += extraPaused;
        _timerPausedAt = null;
        _timerRunning = true;
      });
      await prefs.setInt(_kPausedDurSec, _pausedTotalSec);
    } else {
      setState(() {
        _timerRunning = true;
      });
    }
    await prefs.remove(_kTimerStopped);
    await prefs.remove(_kTimerPausedAt);
    _startTicker();
  }

  // ---------------------------------------------------------------------------
  // Save
  // ---------------------------------------------------------------------------

  Future<void> _save({
    DateTime? manualStartedAt,
    int? manualDurationSeconds,
    double? manualLeftOz,
    double? manualRightOz,
    bool? manualSaveToStash,
    StorageType? manualStorage,
  }) async {
    final babyId = ref.read(currentBabyIdProvider);
    if (babyId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.errorNoBabyProfile)),
      );
      return;
    }

    final prefs = ref.read(sharedPreferencesProvider);
    final repo = ref.read(pumpRepositoryProvider);

    final startedAt = manualStartedAt ?? _timerStartedAt ?? DateTime.now();
    final durationSec = manualDurationSeconds ?? _elapsed.inSeconds;
    final leftOz = manualLeftOz ?? _leftOz;
    final rightOz = manualRightOz ?? _rightOz;
    final note = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    _ticker?.cancel();

    // Determine bottles to stash
    List<PendingBottle> bottlesToSave;
    if (manualSaveToStash == true) {
      // Manual entry: compute bottles from total oz
      final storage = manualStorage ?? StorageType.freezer;
      final total = (manualLeftOz ?? 0) + (manualRightOz ?? 0);
      final portions = <double>[];
      double remaining = total;
      int guard = 0;
      while (remaining > 0.01 && guard++ < 200) {
        final portion = remaining >= _portionOz
            ? _portionOz
            : double.parse(remaining.toStringAsFixed(1));
        if (portion <= 0) break;
        portions.add(portion);
        remaining -= portion;
      }
      bottlesToSave = portions.map((oz) => PendingBottle(oz: oz, storage: storage)).toList();
    } else if (manualSaveToStash == false) {
      bottlesToSave = const [];
    } else {
      // Live session
      bottlesToSave = _saveToStash
          ? _bottles.map((oz) => PendingBottle(oz: oz, storage: _stashStorage)).toList()
          : const [];
    }

    await repo.insert(
      babyId: babyId,
      startedAt: startedAt,
      endedAt: startedAt.add(Duration(seconds: durationSec)),
      leftOz: leftOz,
      rightOz: rightOz,
      durationMin: durationSec ~/ 60,
      note: note,
      bottles: bottlesToSave,
    );

    // Clear all persisted pump timer keys
    await prefs.remove(_kTimerStartedAt);
    await prefs.remove(_kTimerPausedAt);
    await prefs.remove(_kPausedDurSec);
    await prefs.remove(_kTimerStopped);

    unawaited(HapticFeedback.lightImpact());
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  // ---------------------------------------------------------------------------
  // Prefs helpers
  // ---------------------------------------------------------------------------

  Future<void> _persistSide(_Side s) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_kSide, s.name);
  }

  Future<void> _persistSaveToStash(bool v) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_kSaveToStash, v);
  }

  Future<void> _persistStashStorage(StorageType v) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_kStashStorage, v.name);
  }

  Future<void> _persistPortionOz(double v) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setDouble(_kPortionOz, v);
  }

  // ---------------------------------------------------------------------------
  // Bottle splitting
  // ---------------------------------------------------------------------------

  /// Pure function — computes the bottle portion list from current state.
  /// Call inside setState to avoid nested setState calls.
  List<double> _computeBottles() {
    if (!_saveToStash) return [];
    final total = _leftOz + _rightOz;
    if (total <= 0 || _portionOz <= 0) return [];
    final result = <double>[];
    double remaining = total;
    int guard = 0;
    while (remaining > 0.01 && guard++ < 200) {
      final portion = remaining >= _portionOz
          ? _portionOz
          : double.parse(remaining.toStringAsFixed(1));
      if (portion <= 0) break;
      result.add(portion);
      remaining -= portion;
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Manual entry sheet
  // ---------------------------------------------------------------------------

  void _showManualEntry(VolumeUnit unit) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ManualEntrySheet(
        unit: unit,
        onSave: (startedAt, durationMinutes, leftOz, rightOz, saveToStash, storage) {
          Navigator.of(ctx).pop();
          _save(
            manualStartedAt: startedAt,
            manualDurationSeconds: durationMinutes * 60,
            manualLeftOz: leftOz,
            manualRightOz: rightOz,
            manualSaveToStash: saveToStash,
            manualStorage: storage,
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _fmtElapsed(Duration d) {
    final h = d.inHours;
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    if (h > 0) return '$h:$m:$s';
    return '$m:$s';
  }

  bool get _showWarning =>
      _leftOz > 12 || _rightOz > 12 || (_leftOz + _rightOz) > 20;

  double get _totalOz => _leftOz + _rightOz;

  String _fmtTotal(BuildContext context, VolumeUnit unit) {
    if (unit == VolumeUnit.oz) {
      return context.l10n.pumpTotalOz(_totalOz.toStringAsFixed(1));
    }
    return context.l10n.pumpTotalMl('${(_totalOz * _mlPerOz).round()}');
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final unit = ref.watch(unitPreferencesProvider).volume;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: Text(l10n.pumpScreenTitle)),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- Scrollable content ---
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.sm),
                    // --- Timer display ---
                    Center(
                      child: Text(
                        _fmtElapsed(_elapsed),
                        style:
                            AppTypography.statHero(color: scheme.onSurface),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // --- Side toggle ---
                    _SideToggle(
                      side: _side,
                      onChanged: (s) {
                        setState(() {
                          _side = s;
                          if (s == _Side.left) _rightOz = 0;
                          if (s == _Side.right) _leftOz = 0;
                          _bottles = _computeBottles();
                        });
                        _persistSide(s);
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // --- Volume steppers ---
                    _OzSteppers(
                      side: _side,
                      leftOz: _leftOz,
                      rightOz: _rightOz,
                      unit: unit,
                      onLeftChanged: (v) => setState(() {
                        _leftOz = v;
                        _bottles = _computeBottles();
                      }),
                      onRightChanged: (v) => setState(() {
                        _rightOz = v;
                        _bottles = _computeBottles();
                      }),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Center(
                      child: Text(
                        _fmtTotal(context, unit),
                        style: AppTypography.bodyMedium(
                            color: scheme.onSurface.withValues(alpha: 0.6)),
                      ),
                    ),
                    // --- Warning chip ---
                    if (_showWarning) ...[
                      const SizedBox(height: AppSpacing.sm),
                      const _WarningChip(),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    // --- Notes ---
                    TextField(
                      controller: _notesCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: l10n.pumpNotesOptional,
                        hintText: l10n.pumpNotesOptional,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    // --- Save to stash ---
                    CheckboxListTile(
                      value: _saveToStash,
                      onChanged: (v) {
                        final val = v ?? true;
                        setState(() {
                          _saveToStash = val;
                          _bottles = _computeBottles();
                        });
                        _persistSaveToStash(val);
                      },
                      title: Text(l10n.pumpSaveToStash),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (_saveToStash) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: Text(
                          l10n.pumpStashStorage,
                          style: AppTypography.labelLarge(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                        ),
                      ),
                      SegmentedButton<StorageType>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(value: StorageType.freezer, label: Text(l10n.stashStorageFreezer)),
                          ButtonSegment(value: StorageType.fridge, label: Text(l10n.stashStorageFridge)),
                          ButtonSegment(value: StorageType.room, label: Text(l10n.stashStorageRoom)),
                        ],
                        selected: {_stashStorage},
                        onSelectionChanged: (s) {
                          setState(() => _stashStorage = s.first);
                          _persistStashStorage(s.first);
                        },
                      ),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    // --- Bottle preview ---
                    if (_saveToStash && (_leftOz + _rightOz) > 0) ...[
                      _BottlePreviewSection(
                        bottles: _bottles,
                        portionOz: _portionOz,
                        unit: unit,
                        onPortionChanged: (v) {
                          setState(() {
                            _portionOz = v;
                            _bottles = _computeBottles();
                          });
                          _persistPortionOz(v);
                        },
                        onRemoveBottle: (index) {
                          setState(() {
                            _bottles = List.of(_bottles)..removeAt(index);
                          });
                        },
                        onAddBottle: () {
                          setState(() {
                            _bottles = List.of(_bottles)..add(_portionOz);
                          });
                        },
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    // --- Manual entry ---
                    TextButton(
                      onPressed: () => _showManualEntry(unit),
                      child: Text(context.l10n.pumpAddPast),
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
                            _PumpTodaySummary(babyId: babyId),
                            PumpHistorySection(babyId: babyId),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                ),
              ),
            ),
            // --- Fixed bottom thumb-zone buttons ---
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.lg,
              ),
              child: _BottomButtons(
                timerStartedEver: _timerStartedEver,
                timerRunning: _timerRunning,
                onStart: _onStart,
                onStop: _onStop,
                onPause: _onPause,
                onResume: _onResume,
                onSave: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Volume conversion helpers
// ---------------------------------------------------------------------------

const _mlPerOz = 29.5735;

double _stepFor(VolumeUnit u) => u == VolumeUnit.oz ? 0.5 : 5.0 / _mlPerOz;
double _maxFor(VolumeUnit u) => u == VolumeUnit.oz ? 16.0 : 500.0 / _mlPerOz;

String _fmtVol(double oz, VolumeUnit u) => u == VolumeUnit.oz
    ? '${oz.toStringAsFixed(1)} oz'
    : '${(oz * _mlPerOz).round()} ml';

// ---------------------------------------------------------------------------
// Side toggle widget
// ---------------------------------------------------------------------------

class _SideToggle extends StatelessWidget {
  const _SideToggle({required this.side, required this.onChanged});

  final _Side side;
  final ValueChanged<_Side> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SegmentedButton<_Side>(
      segments: [
        ButtonSegment(value: _Side.both, label: Text(l10n.pumpBothSides)),
        ButtonSegment(value: _Side.left, label: Text(l10n.pumpLeftOnly)),
        ButtonSegment(value: _Side.right, label: Text(l10n.pumpRightOnly)),
      ],
      selected: {side},
      onSelectionChanged: (s) => onChanged(s.first),
    );
  }
}

// ---------------------------------------------------------------------------
// Oz steppers widget
// ---------------------------------------------------------------------------

class _OzSteppers extends StatelessWidget {
  const _OzSteppers({
    required this.side,
    required this.leftOz,
    required this.rightOz,
    required this.unit,
    required this.onLeftChanged,
    required this.onRightChanged,
  });

  final _Side side;
  final double leftOz;
  final double rightOz;
  final VolumeUnit unit;
  final ValueChanged<double> onLeftChanged;
  final ValueChanged<double> onRightChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Both sides: show left and right columns next to each other
    if (side == _Side.both) {
      return IntrinsicHeight(
        child: Row(
          children: [
            Expanded(
              child: _OzColumn(
                label: l10n.pumpSideLeft,
                value: leftOz,
                unit: unit,
                onChanged: onLeftChanged,
              ),
            ),
            const VerticalDivider(width: 1, indent: 8, endIndent: 8),
            Expanded(
              child: _OzColumn(
                label: l10n.pumpSideRight,
                value: rightOz,
                unit: unit,
                onChanged: onRightChanged,
              ),
            ),
          ],
        ),
      );
    }
    // Single side: centered column layout
    return Center(
      child: _OzColumn(
        label: side == _Side.left ? l10n.pumpSideLeft : l10n.pumpSideRight,
        value: side == _Side.left ? leftOz : rightOz,
        unit: unit,
        onChanged: side == _Side.left ? onLeftChanged : onRightChanged,
      ),
    );
  }
}

/// Compact vertical layout used when both sides are shown side-by-side.
class _OzColumn extends StatelessWidget {
  const _OzColumn({
    required this.label,
    required this.value,
    required this.unit,
    required this.onChanged,
  });

  final String label;
  final double value;
  final VolumeUnit unit;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final step = _stepFor(unit);
    final max = _maxFor(unit);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.labelLarge(color: scheme.onSurface.withValues(alpha: 0.6)),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _fmtVol(value, unit),
          style: AppTypography.numeric(size: 20, weight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filled(
              onPressed: value <= 0.0
                  ? null
                  : () => onChanged(double.parse(
                      (value - step).clamp(0.0, max).toStringAsFixed(5))),
              icon: const Icon(Icons.remove, size: 18),
              iconSize: 18,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filled(
              onPressed: value >= max
                  ? null
                  : () => onChanged(double.parse(
                      (value + step).clamp(0.0, max).toStringAsFixed(5))),
              icon: const Icon(Icons.add, size: 18),
              iconSize: 18,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ],
    );
  }
}

class _OzRow extends StatelessWidget {
  const _OzRow({
    required this.label,
    required this.value,
    required this.unit,
    required this.onChanged,
  });

  final String label;
  final double value; // always stored in oz
  final VolumeUnit unit;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final step = _stepFor(unit);
    final max = _maxFor(unit);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: AppTypography.bodyMedium(color: scheme.onSurface.withValues(alpha: 0.6)),
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        IconButton.filled(
          onPressed: value <= 0.0 ? null : () => onChanged(
            double.parse((value - step).clamp(0.0, max).toStringAsFixed(5)),
          ),
          icon: const Icon(Icons.remove),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 68,
          child: Text(
            _fmtVol(value, unit),
            style: AppTypography.numeric(size: 18, weight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        IconButton.filled(
          onPressed: value >= max ? null : () => onChanged(
            double.parse((value + step).clamp(0.0, max).toStringAsFixed(5)),
          ),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Warning chip
// ---------------------------------------------------------------------------

class _WarningChip extends StatelessWidget {
  const _WarningChip();

  @override
  Widget build(BuildContext context) {
    return Chip(
      backgroundColor: const Color(0x40CC8020), // lightWarning at ~25% opacity
      label: Text(
        context.l10n.pumpWarningHighVolume,
        style: const TextStyle(color: AppColors.honey700),
      ),
      avatar: const Icon(Icons.warning_amber_rounded, color: AppColors.honey700),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom thumb-zone buttons
// ---------------------------------------------------------------------------

class _BottomButtons extends StatelessWidget {
  const _BottomButtons({
    required this.timerStartedEver,
    required this.timerRunning,
    required this.onStart,
    required this.onStop,
    required this.onPause,
    required this.onResume,
    required this.onSave,
  });

  final bool timerStartedEver;
  final bool timerRunning;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    if (!timerStartedEver) {
      // Not started yet — full-width Start button
      return FilledButton(
        onPressed: onStart,
        child: Text(context.l10n.pumpStart),
      );
    }

    if (timerRunning) {
      // Running → Stop | Pause
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onStop,
              child: Text(context.l10n.pumpStop),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: FilledButton(
              onPressed: onPause,
              child: Text(context.l10n.pumpPause),
            ),
          ),
        ],
      );
    }

    // Stopped (but started) → Resume | Save
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: onResume,
            child: Text(context.l10n.pumpResume),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: FilledButton(
            onPressed: onSave,
            child: Text(context.l10n.actionSave),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Bottle preview section
// ---------------------------------------------------------------------------

class _BottlePreviewSection extends StatelessWidget {
  const _BottlePreviewSection({
    required this.bottles,
    required this.portionOz,
    required this.unit,
    required this.onPortionChanged,
    required this.onRemoveBottle,
    required this.onAddBottle,
  });

  final List<double> bottles;
  final double portionOz; // always in oz
  final VolumeUnit unit;
  final ValueChanged<double> onPortionChanged;
  final ValueChanged<int> onRemoveBottle;
  final VoidCallback onAddBottle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header row: label + per-bottle stepper
        Row(
          children: [
            Text(
              l10n.pumpBottlePortions,
              style:
                  AppTypography.labelLarge(color: scheme.onSurface.withValues(alpha: 0.6)),
            ),
            const Spacer(),
            // Per-bottle stepper
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.pumpPerBottle,
                  style: AppTypography.labelLarge(color: scheme.onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: portionOz <= 0.0
                      ? null
                      : () => onPortionChanged(
                            double.parse(
                                (portionOz - _stepFor(unit)).clamp(0.0, _maxFor(unit)).toStringAsFixed(5)),
                          ),
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 52,
                  child: Text(
                    _fmtVol(portionOz, unit),
                    style: AppTypography.numeric(size: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: portionOz >= _maxFor(unit)
                      ? null
                      : () => onPortionChanged(
                            double.parse(
                                (portionOz + _stepFor(unit)).clamp(0.0, _maxFor(unit)).toStringAsFixed(5)),
                          ),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        // Chips row
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (int i = 0; i < bottles.length; i++)
              _BottleChip(
                oz: bottles[i],
                unit: unit,
                onDeleted: () => onRemoveBottle(i),
              ),
          ],
        ),
        // Add bottle button
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onAddBottle,
            child: Text(context.l10n.pumpAddBottle),
          ),
        ),
      ],
    );
  }
}

class _BottleChip extends StatelessWidget {
  const _BottleChip({required this.oz, required this.unit, required this.onDeleted});

  final double oz; // always in oz
  final VolumeUnit unit;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(_fmtVol(oz, unit)),
      backgroundColor: AppColors.lightSuccess.withValues(alpha: 0.3),
      onDeleted: onDeleted,
    );
  }
}

// ---------------------------------------------------------------------------
// Today summary bar
// ---------------------------------------------------------------------------

class _PumpTodaySummary extends ConsumerWidget {
  const _PumpTodaySummary({required this.babyId});
  final String babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return ref.watch(pumpTodayProvider(babyId)).when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (sessions) {
        final String detail;
        if (sessions.isEmpty) {
          detail = l10n.todayNoPumpsYet;
        } else {
          final totalOz = sessions.fold<double>(
            0.0,
            (sum, s) => sum + s.leftOz + s.rightOz,
          );
          detail = '${sessions.length} ${sessions.length == 1 ? 'session' : 'sessions'} · ${totalOz.toStringAsFixed(1)} oz total';
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

// ---------------------------------------------------------------------------
// Manual entry bottom sheet
// ---------------------------------------------------------------------------

class _ManualEntrySheet extends StatefulWidget {
  const _ManualEntrySheet({required this.unit, required this.onSave});

  final VolumeUnit unit;
  final void Function(
    DateTime startedAt,
    int durationMinutes,
    double leftOz,
    double rightOz,
    bool saveToStash,
    StorageType storage,
  ) onSave;

  @override
  State<_ManualEntrySheet> createState() => _ManualEntrySheetState();
}

class _ManualEntrySheetState extends State<_ManualEntrySheet> {
  DateTime? _startedAt;
  int _durationMinutes = 0;
  double _leftOz = 0;
  double _rightOz = 0;
  bool _saveToStash = false;
  StorageType _storage = StorageType.freezer;

  @override
  void initState() {
    super.initState();
    // Leave _startedAt null — show 2 buttons initially.
  }

  Future<void> _pickToday() async {
    final picked = await pickTodayTime(context);
    if (picked != null && mounted) setState(() => _startedAt = picked);
  }

  Future<void> _pickPast() async {
    final picked = await pickPastDateTime(context, _startedAt);
    if (picked != null && mounted) setState(() => _startedAt = picked);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: AppSpacing.md,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.pumpAddPastTitle,
            style: AppTypography.titleLarge(color: scheme.onSurface),
          ),
          const SizedBox(height: AppSpacing.md),
          // Started at — 2-button + chip time picker
          Text(
            l10n.pumpStartedAtLabel,
            style: AppTypography.bodyMedium(color: scheme.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: AppSpacing.xs),
          LoggedAtChip(
            value: _startedAt,
            onTapToday: _pickToday,
            onTapPast: _pickPast,
            onClear: _startedAt != null
                ? () => setState(() => _startedAt = null)
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          // Duration
          Row(
            children: [
              Text(
                l10n.pumpDurationLabel,
                style: AppTypography.bodyMedium(color: scheme.onSurface.withValues(alpha: 0.6)),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                onPressed: _durationMinutes <= 0
                    ? null
                    : () => setState(() => _durationMinutes--),
                icon: const Icon(Icons.remove),
              ),
              Text(
                '$_durationMinutes',
                style: AppTypography.numeric(size: 18),
              ),
              IconButton(
                onPressed: () => setState(() => _durationMinutes++),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Volume steppers
          _OzRow(
            label: l10n.pumpSideLeft,
            value: _leftOz,
            unit: widget.unit,
            onChanged: (v) => setState(() => _leftOz = v),
          ),
          const SizedBox(height: AppSpacing.xs),
          _OzRow(
            label: l10n.pumpSideRight,
            value: _rightOz,
            unit: widget.unit,
            onChanged: (v) => setState(() => _rightOz = v),
          ),
          const SizedBox(height: AppSpacing.sm),
          CheckboxListTile(
            value: _saveToStash,
            onChanged: (v) => setState(() => _saveToStash = v ?? false),
            title: Text(l10n.pumpSaveToStash),
            contentPadding: EdgeInsets.zero,
          ),
          if (_saveToStash) ...[
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                l10n.pumpStashStorage,
                style: AppTypography.labelLarge(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
            ),
            SegmentedButton<StorageType>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: StorageType.freezer, label: Text(l10n.stashStorageFreezer)),
                ButtonSegment(value: StorageType.fridge, label: Text(l10n.stashStorageFridge)),
                ButtonSegment(value: StorageType.room, label: Text(l10n.stashStorageRoom)),
              ],
              selected: {_storage},
              onSelectionChanged: (s) => setState(() => _storage = s.first),
            ),
            const SizedBox(height: AppSpacing.xs),
          ],
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _startedAt == null
                ? null
                : () => widget.onSave(
                      _startedAt!,
                      _durationMinutes,
                      _leftOz,
                      _rightOz,
                      _saveToStash,
                      _storage,
                    ),
            child: Text(l10n.actionSave),
          ),
        ],
      ),
    );
  }
}
