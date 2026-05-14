import 'dart:async';

import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/sleep/data/sleep_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// ---------------------------------------------------------------------------
// SharedPreferences keys (crash recovery)
// ---------------------------------------------------------------------------

const _kSleepStartedAt = 'sleep.activeStartedAt'; // ISO-8601
const _kSleepId = 'sleep.activeId'; // UUID

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

/// Sleep tracking screen — serves double duty:
/// - No active session → "Start sleep" mode with location + notes input
/// - Active session    → live timer display + "Wake Up" button
///
/// State is persisted to SharedPreferences so a crash / background kill
/// mid-session can be recovered on re-open.
class SleepTimerScreen extends ConsumerStatefulWidget {
  const SleepTimerScreen({super.key});

  @override
  ConsumerState<SleepTimerScreen> createState() => _SleepTimerScreenState();
}

class _SleepTimerScreenState extends ConsumerState<SleepTimerScreen> {
  // --- Sleep state ---
  String? _activeSleepId;
  DateTime? _activeSleepStartedAt;

  // --- Timer state ---
  Duration _elapsed = Duration.zero;
  Timer? _ticker;

  // --- Form state ---
  SleepLocation _location = SleepLocation.crib;
  final _notesCtrl = TextEditingController();

  bool get _isActive => _activeSleepId != null;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    // Load active session from SharedPreferences (crash recovery) or
    // from the provider (normal app lifecycle).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadState();
    });
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
      // No prefs → check DB via provider
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
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Timer
  // ---------------------------------------------------------------------------

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _activeSleepStartedAt != null) {
        setState(() {
          _elapsed = DateTime.now().difference(_activeSleepStartedAt!);
        });
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
        const SnackBar(content: Text('No baby selected')),
      );
      return;
    }

    final prefs = ref.read(sharedPreferencesProvider);
    final repo = ref.read(sleepRepositoryProvider);
    final now = DateTime.now();
    final note =
        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

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

    final ended = await repo.end(
      _activeSleepId!,
      babyId: babyId,
      endedAt: now,
    );

    await prefs.remove(_kSleepStartedAt);
    await prefs.remove(_kSleepId);

    _ticker?.cancel();

    if (!mounted) return;

    // Show a quick summary snackbar
    final totalMin = ended.durationMin ?? _elapsed.inMinutes;
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    final summary =
        h > 0 ? 'Slept for ${h}h ${m}m' : 'Slept for ${m}m';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(summary)),
    );

    context.pop();
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

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isActive ? 'Sleeping... 💤' : 'Sleep'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.lg,
          ),
          child: _isActive ? _buildActiveBody() : _buildIdleBody(),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Idle body (no active session)
  // ---------------------------------------------------------------------------

  Widget _buildIdleBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Moon icon
        const Center(
          child: Icon(
            Icons.bedtime_outlined,
            size: 80,
            color: AppColors.lavender700,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: Text(
            'Tap Start to begin tracking',
            style: AppTypography.bodyMedium(color: AppColors.inkSecondary),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Location selector
        SegmentedButton<SleepLocation>(
          segments: const [
            ButtonSegment(
              value: SleepLocation.crib,
              label: Text('Crib'),
            ),
            ButtonSegment(
              value: SleepLocation.stroller,
              label: Text('Stroller'),
            ),
            ButtonSegment(
              value: SleepLocation.car,
              label: Text('Car'),
            ),
            ButtonSegment(
              value: SleepLocation.other,
              label: Text('Other'),
            ),
          ],
          selected: {_location},
          onSelectionChanged: (s) => setState(() => _location = s.first),
        ),
        const SizedBox(height: AppSpacing.md),

        // Notes field
        TextField(
          controller: _notesCtrl,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            hintText: 'Notes (optional)',
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Start button
        FilledButton(
          onPressed: _onStart,
          child: const Text('Start'),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Active body (session in progress)
  // ---------------------------------------------------------------------------

  Widget _buildActiveBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Elapsed timer
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
              'Started at ${_fmtTime(_activeSleepStartedAt!)}',
              style: AppTypography.bodyMedium(color: AppColors.inkSecondary),
            ),
          ),
        ],

        const SizedBox(height: AppSpacing.xl),

        // Wake Up button
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.lightSuccess,
          ),
          onPressed: _onWakeUp,
          child: const Text('Wake Up'),
        ),
      ],
    );
  }
}
