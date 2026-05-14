import 'dart:async';

import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/pump/data/pump_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// SharedPreferences keys
// ---------------------------------------------------------------------------

const _kTimerStartedAt = 'pump.timerStartedAt'; // ISO-8601 string
const _kTimerPausedAt = 'pump.timerPausedAt'; // ISO-8601 string
const _kPausedDurSec = 'pump.timerPausedDurSec'; // int
const _kSaveToStash = 'pump.saveToStash'; // bool
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

    // Restore portion oz preference
    _portionOz = prefs.getDouble(_kPortionOz) ?? 4.0;
    _bottles = _computeBottles();

    // Recover in-progress timer
    final startedAtStr = prefs.getString(_kTimerStartedAt);
    if (startedAtStr != null) {
      _timerStartedAt = DateTime.parse(startedAtStr);
      _timerStartedEver = true;
      _timerRunning = true;
      _pausedTotalSec = prefs.getInt(_kPausedDurSec) ?? 0;

      // Check if it was paused when the app was killed
      final pausedAtStr = prefs.getString(_kTimerPausedAt);
      if (pausedAtStr != null) {
        _timerPausedAt = DateTime.parse(pausedAtStr);
        _timerRunning = false;
        // Calculate elapsed up to when it was paused
        _elapsed = _timerPausedAt!.difference(_timerStartedAt!) -
            Duration(seconds: _pausedTotalSec);
      } else {
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
    await prefs.setInt(_kPausedDurSec, _pausedTotalSec);
  }

  Future<void> _onStop() async {
    final prefs = ref.read(sharedPreferencesProvider);
    _ticker?.cancel();
    setState(() {
      _elapsed = _currentElapsed;
      _timerRunning = false;
    });
    // Keep _kTimerStartedAt in prefs so Save can read it; clear paused marker
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
  }) async {
    final babyId = ref.read(currentBabyIdProvider);
    if (babyId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No baby selected')),
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

    await repo.insert(
      babyId: babyId,
      startedAt: startedAt,
      endedAt: startedAt.add(Duration(seconds: durationSec)),
      leftOz: leftOz,
      rightOz: rightOz,
      durationMin: durationSec ~/ 60,
      note: note,
      bottles: _saveToStash
          ? _bottles.map((oz) => PendingBottle(oz: oz)).toList()
          : const [],
    );

    // Clear all persisted pump timer keys
    await prefs.remove(_kTimerStartedAt);
    await prefs.remove(_kTimerPausedAt);
    await prefs.remove(_kPausedDurSec);

    unawaited(HapticFeedback.lightImpact());
    if (!mounted) return;
    context.pop();
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
    while (remaining > 0.01) {
      final portion = remaining >= _portionOz
          ? _portionOz
          : double.parse(remaining.toStringAsFixed(1));
      result.add(portion);
      remaining -= portion;
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Manual entry sheet
  // ---------------------------------------------------------------------------

  void _showManualEntry() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ManualEntrySheet(
        onSave: (startedAt, durationMinutes, leftOz, rightOz) {
          Navigator.of(ctx).pop();
          _save(
            manualStartedAt: startedAt,
            manualDurationSeconds: durationMinutes * 60,
            manualLeftOz: leftOz,
            manualRightOz: rightOz,
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

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
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
                            AppTypography.statHero(color: AppColors.inkPrimary),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // --- Side toggle ---
                    _SideToggle(
                      side: _side,
                      onChanged: (s) {
                        setState(() => _side = s);
                        _persistSide(s);
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // --- Oz steppers ---
                    _OzSteppers(
                      side: _side,
                      leftOz: _leftOz,
                      rightOz: _rightOz,
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
                        'Total: ${_totalOz.toStringAsFixed(1)} oz',
                        style: AppTypography.bodyMedium(
                            color: AppColors.inkSecondary),
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
                      decoration: const InputDecoration(
                        labelText: 'Notes (optional)',
                        hintText: 'Notes (optional)',
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
                    // --- Bottle preview ---
                    if (_saveToStash && (_leftOz + _rightOz) > 0) ...[
                      _BottlePreviewSection(
                        bottles: _bottles,
                        portionOz: _portionOz,
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
                      onPressed: _showManualEntry,
                      child: const Text('+ Add past pump'),
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
// Side toggle widget
// ---------------------------------------------------------------------------

class _SideToggle extends StatelessWidget {
  const _SideToggle({required this.side, required this.onChanged});

  final _Side side;
  final ValueChanged<_Side> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_Side>(
      segments: const [
        ButtonSegment(value: _Side.both, label: Text('Both')),
        ButtonSegment(value: _Side.left, label: Text('L only')),
        ButtonSegment(value: _Side.right, label: Text('R only')),
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
    required this.onLeftChanged,
    required this.onRightChanged,
  });

  final _Side side;
  final double leftOz;
  final double rightOz;
  final ValueChanged<double> onLeftChanged;
  final ValueChanged<double> onRightChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (side == _Side.both || side == _Side.left)
          _OzRow(
            label: 'Left (oz)',
            value: leftOz,
            onChanged: onLeftChanged,
          ),
        if (side == _Side.both) const SizedBox(height: AppSpacing.sm),
        if (side == _Side.both || side == _Side.right)
          _OzRow(
            label: 'Right (oz)',
            value: rightOz,
            onChanged: onRightChanged,
          ),
      ],
    );
  }
}

class _OzRow extends StatelessWidget {
  const _OzRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: AppTypography.bodyMedium(color: AppColors.inkSecondary),
            textAlign: TextAlign.right,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        IconButton.filled(
          onPressed: value <= 0.0 ? null : () => onChanged(value - 0.5),
          icon: const Icon(Icons.remove),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 56,
          child: Text(
            value.toStringAsFixed(1),
            style: AppTypography.numeric(size: 20, weight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        IconButton.filled(
          onPressed: () => onChanged(value + 0.5),
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
    return const Chip(
      backgroundColor: Color(0xFFFFC107),
      label: Text(
        'Unusually high volume — double-check?',
        style: TextStyle(color: Colors.black87),
      ),
      avatar: Icon(Icons.warning_amber_rounded, color: Colors.black87),
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
        child: const Text('Start'),
      );
    }

    if (timerRunning) {
      // Running → Stop | Pause
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onStop,
              child: const Text('Stop'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: FilledButton(
              onPressed: onPause,
              child: const Text('Pause'),
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
            child: const Text('Resume'),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: FilledButton(
            onPressed: onSave,
            child: const Text('Save'),
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
    required this.onPortionChanged,
    required this.onRemoveBottle,
    required this.onAddBottle,
  });

  final List<double> bottles;
  final double portionOz;
  final ValueChanged<double> onPortionChanged;
  final ValueChanged<int> onRemoveBottle;
  final VoidCallback onAddBottle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header row: label + per-bottle stepper
        Row(
          children: [
            Text(
              'Bottle portions',
              style:
                  AppTypography.labelLarge(color: AppColors.inkSecondary),
            ),
            const Spacer(),
            // Per-bottle stepper
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Per bottle:',
                  style: AppTypography.labelLarge(color: AppColors.inkSecondary),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: portionOz <= 0.5
                      ? null
                      : () => onPortionChanged(
                            double.parse(
                                (portionOz - 0.5).toStringAsFixed(1)),
                          ),
                  icon: const Icon(Icons.remove),
                ),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${portionOz.toStringAsFixed(1)} oz',
                    style: AppTypography.numeric(size: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: portionOz >= 16
                      ? null
                      : () => onPortionChanged(
                            double.parse(
                                (portionOz + 0.5).toStringAsFixed(1)),
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
                onDeleted: () => onRemoveBottle(i),
              ),
          ],
        ),
        // Add bottle button
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: onAddBottle,
            child: const Text('+ Add bottle'),
          ),
        ),
      ],
    );
  }
}

class _BottleChip extends StatelessWidget {
  const _BottleChip({required this.oz, required this.onDeleted});

  final double oz;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text('${oz.toStringAsFixed(1)} oz'),
      backgroundColor: AppColors.lightSuccess.withValues(alpha: 0.3),
      onDeleted: onDeleted,
    );
  }
}

// ---------------------------------------------------------------------------
// Manual entry bottom sheet
// ---------------------------------------------------------------------------

class _ManualEntrySheet extends StatefulWidget {
  const _ManualEntrySheet({required this.onSave});

  final void Function(
    DateTime startedAt,
    int durationMinutes,
    double leftOz,
    double rightOz,
  ) onSave;

  @override
  State<_ManualEntrySheet> createState() => _ManualEntrySheetState();
}

class _ManualEntrySheetState extends State<_ManualEntrySheet> {
  late DateTime _startedAt;
  int _durationMinutes = 0;
  double _leftOz = 0;
  double _rightOz = 0;

  @override
  void initState() {
    super.initState();
    // Default: now - 1 hour, rounded down to nearest 15 min
    final now = DateTime.now();
    final oneHourAgo = now.subtract(const Duration(hours: 1));
    final minutes = (oneHourAgo.minute ~/ 15) * 15;
    _startedAt = DateTime(
      oneHourAgo.year,
      oneHourAgo.month,
      oneHourAgo.day,
      oneHourAgo.hour,
      minutes,
    );
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
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
            'Add past pump',
            style: AppTypography.titleLarge(color: AppColors.inkPrimary),
          ),
          const SizedBox(height: AppSpacing.md),
          // Started at
          Row(
            children: [
              Text(
                'Started at:',
                style: AppTypography.bodyMedium(color: AppColors.inkSecondary),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton(
                onPressed: () {
                  setState(() {
                    _startedAt =
                        _startedAt.subtract(const Duration(minutes: 15));
                  });
                },
                icon: const Icon(Icons.remove),
              ),
              Text(_fmtTime(_startedAt),
                  style: AppTypography.numeric(size: 18)),
              IconButton(
                onPressed: () {
                  setState(() {
                    _startedAt = _startedAt.add(const Duration(minutes: 15));
                  });
                },
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // Duration
          Row(
            children: [
              Text(
                'Duration (min):',
                style: AppTypography.bodyMedium(color: AppColors.inkSecondary),
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
          // Oz steppers
          _OzRow(
            label: 'Left (oz)',
            value: _leftOz,
            onChanged: (v) => setState(() => _leftOz = v),
          ),
          const SizedBox(height: AppSpacing.xs),
          _OzRow(
            label: 'Right (oz)',
            value: _rightOz,
            onChanged: (v) => setState(() => _rightOz = v),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: () =>
                widget.onSave(_startedAt, _durationMinutes, _leftOz, _rightOz),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
