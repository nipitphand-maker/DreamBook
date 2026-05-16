import 'dart:async';

import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/models/temp_reading.dart';
import 'package:dreambook/core/providers/unit_preferences_provider.dart';
import 'package:dreambook/core/router/app_router.dart';
import 'package:dreambook/core/services/unit_preferences.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/core/widgets/logged_at_chip.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/temperature/data/temp_reading_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

class TemperatureScreen extends ConsumerStatefulWidget {
  const TemperatureScreen({super.key});

  @override
  ConsumerState<TemperatureScreen> createState() => _TemperatureScreenState();
}

class _TemperatureScreenState extends ConsumerState<TemperatureScreen> {
  final _ctrl = TextEditingController();
  DateTime? _loggedAt;
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  TempUnit get _unit => ref.read(temperatureUnitProvider);

  Future<void> _save() async {
    final raw = double.tryParse(_ctrl.text.trim());
    if (raw == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.errorGeneric)),
      );
      return;
    }

    final babyId = ref.read(currentBabyIdProvider);
    if (babyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.errorNoBabyProfile)),
      );
      return;
    }

    final celsius =
        _unit == TempUnit.fahrenheit ? TempReading.toC(raw) : raw;

    setState(() => _saving = true);
    try {
      final now = DateTime.now().toUtc();
      final reading = TempReading(
        id: const Uuid().v4(),
        babyId: babyId,
        takenAt: (_loggedAt ?? DateTime.now()).toUtc(),
        celsius: celsius,
        version: 1,
        updatedAt: now,
      );
      await ref.read(tempReadingRepositoryProvider).insert(reading);

      unawaited(HapticFeedback.lightImpact());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.tempSaved)),
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(AppRoutes.home);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final unit = ref.watch(temperatureUnitProvider);
    final babyId = ref.watch(currentBabyIdProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tempTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: l10n.tempTitle,
                        suffixText: unit == TempUnit.fahrenheit
                            ? l10n.tempUnitFahrenheit
                            : l10n.tempUnitCelsius,
                      ),
                      autofocus: true,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _UnitToggle(
                    unit: unit,
                    onChanged: (u) =>
                        ref.read(unitPreferencesProvider.notifier).setTemp(u),
                  ),
                ],
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
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(l10n.actionSave),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (babyId != null) ...[
                const Divider(),
                _TempHistory(babyId: babyId),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UnitToggle extends StatelessWidget {
  const _UnitToggle({required this.unit, required this.onChanged});
  final TempUnit unit;
  final ValueChanged<TempUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<TempUnit>(
      segments: const [
        ButtonSegment(value: TempUnit.celsius, label: Text('°C')),
        ButtonSegment(value: TempUnit.fahrenheit, label: Text('°F')),
      ],
      selected: {unit},
      onSelectionChanged: (s) => onChanged(s.first),
      showSelectedIcon: false,
    );
  }
}

class _TempHistory extends ConsumerWidget {
  const _TempHistory({required this.babyId});
  final String babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final unit = ref.watch(temperatureUnitProvider);
    final async = ref.watch(tempReadingsProvider(babyId));

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const SizedBox.shrink(),
      data: (readings) {
        if (readings.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Text(
              l10n.tempHistoryEmpty,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
          );
        }
        final recent = readings.take(10).toList();
        return Expanded(
          child: ListView.separated(
            itemCount: recent.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: AppSpacing.xxs),
            itemBuilder: (_, i) => _TempRow(reading: recent[i], unit: unit),
          ),
        );
      },
    );
  }
}

class _TempRow extends StatelessWidget {
  const _TempRow({required this.reading, required this.unit});
  final TempReading reading;
  final TempUnit unit;

  @override
  Widget build(BuildContext context) {
    final isFever = reading.celsius >= 38.0;
    final scheme = Theme.of(context).colorScheme;
    final valueColor = isFever ? scheme.error : scheme.onSurface;

    final displayValue = unit == TempUnit.fahrenheit
        ? reading.fahrenheit
        : reading.celsius;
    final unitLabel =
        unit == TempUnit.fahrenheit ? '°F' : '°C';
    final timeLabel =
        DateFormat.jm().format(reading.takenAt.toLocal());

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(
            Icons.thermostat_outlined,
            size: 18,
            color: isFever ? scheme.error : scheme.onSurface.withValues(alpha: 0.6),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '${displayValue.toStringAsFixed(1)}$unitLabel',
            style: AppTypography.numeric(
              size: 15,
              weight: FontWeight.w700,
              color: valueColor,
            ),
          ),
          if (isFever) ...[
            const SizedBox(width: AppSpacing.xs),
            Text(
              context.l10n.tempFever,
              style: AppTypography.labelLarge(color: scheme.error),
            ),
          ],
          const Spacer(),
          Text(
            timeLabel,
            style: AppTypography.numeric(
              size: 13,
              weight: FontWeight.w400,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}
