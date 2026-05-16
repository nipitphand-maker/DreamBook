import 'dart:async';

import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/services/notification_service.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/core/widgets/logged_at_chip.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/medication/data/medication_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

const _kNextDoseNotifId = 300;
const _kDrugNameMaxLen = 120;
const _uuid = Uuid();

class MedicationScreen extends ConsumerStatefulWidget {
  const MedicationScreen({super.key});

  @override
  ConsumerState<MedicationScreen> createState() => _MedicationScreenState();
}

class _MedicationScreenState extends ConsumerState<MedicationScreen> {
  final _drugNameCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _unit = 'mg';
  DateTime? _givenAt;
  DateTime? _nextDoseAt;
  bool _saving = false;

  @override
  void dispose() {
    _drugNameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickGivenAtToday() async {
    final picked = await pickTodayTime(context);
    if (picked != null && mounted) setState(() => _givenAt = picked);
  }

  Future<void> _pickGivenAtPast() async {
    final picked = await pickPastDateTime(context, _givenAt);
    if (picked != null && mounted) setState(() => _givenAt = picked);
  }

  Future<void> _pickNextDose() async {
    final now = DateTime.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: (now.hour + 4) % 24,
        minute: now.minute,
      ),
    );
    if (picked == null || !mounted) return;
    final today = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
    final candidate = today.isAfter(now) ? today : today.add(const Duration(days: 1));
    setState(() => _nextDoseAt = candidate);
  }

  void _clearNextDose() => setState(() => _nextDoseAt = null);

  Future<void> _save() async {
    final drug = _drugNameCtrl.text.trim();
    if (drug.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.medErrorEmptyDrugName)),
      );
      return;
    }
    final amountText = _amountCtrl.text.trim();
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.medErrorInvalidAmount)),
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

    final l10n = context.l10n;
    final notifTitle = l10n.medNotifTitle;
    final notifBody = l10n.medNotifBody(drug);
    final savedMsg = l10n.medSaved;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _saving = true);
    try {
      final now = DateTime.now().toUtc();
      final dose = MedicationDose(
        id: _uuid.v4(),
        babyId: babyId,
        drugName: drug,
        doseAmount: amount,
        doseUnit: _unit,
        givenAt: (_givenAt ?? DateTime.now()).toUtc(),
        nextDoseAt: _nextDoseAt?.toUtc(),
        version: 1,
        updatedAt: now,
      );

      await ref.read(medicationRepositoryProvider).insert(dose);

      await NotificationService.cancel(_kNextDoseNotifId);
      if (_nextDoseAt != null && _nextDoseAt!.isAfter(DateTime.now())) {
        await NotificationService.scheduleInexact(
          id: _kNextDoseNotifId,
          title: notifTitle,
          body: notifBody,
          when: _nextDoseAt!,
        );
      }

      ref.invalidate(medicationTodayProvider(babyId));

      unawaited(HapticFeedback.lightImpact());
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(savedMsg)),
      );

      _drugNameCtrl.clear();
      _amountCtrl.clear();
      setState(() {
        _unit = 'mg';
        _givenAt = null;
        _nextDoseAt = null;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final babyId = ref.watch(currentBabyIdProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.medTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _drugNameCtrl,
                        maxLength: _kDrugNameMaxLen,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: l10n.medTitle,
                          hintText: l10n.medDrugNameHint,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: _amountCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: l10n.medDoseAmount,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            flex: 2,
                            child: DropdownButton<String>(
                              value: _unit,
                              isExpanded: true,
                              items: [
                                DropdownMenuItem(value: 'mg', child: Text(l10n.medUnitMg)),
                                DropdownMenuItem(value: 'ml', child: Text(l10n.medUnitMl)),
                                DropdownMenuItem(value: 'tablet', child: Text(l10n.medUnitTablet)),
                              ],
                              onChanged: (v) {
                                if (v != null) setState(() => _unit = v);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      LoggedAtChip(
                        value: _givenAt,
                        onTapToday: _pickGivenAtToday,
                        onTapPast: _pickGivenAtPast,
                        onClear: _givenAt != null
                            ? () => setState(() => _givenAt = null)
                            : null,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (_nextDoseAt == null)
                        TextButton.icon(
                          onPressed: _pickNextDose,
                          icon: const Icon(Icons.alarm_add_outlined),
                          label: Text(l10n.medSetNextDose),
                        )
                      else
                        Row(
                          children: [
                            const Icon(Icons.alarm_outlined, size: 18, color: AppColors.honey700),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              l10n.medNextDoseAt(_fmtTime(_nextDoseAt!)),
                              style: AppTypography.labelLarge(color: AppColors.honey700),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: _clearNextDose,
                              tooltip: l10n.actionCancel,
                            ),
                          ],
                        ),
                      const SizedBox(height: AppSpacing.md),
                      FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(l10n.actionSave),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (babyId != null) ...[
                        const Divider(),
                        _MedicationTodayList(babyId: babyId),
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

String _fmtTime(DateTime dt) {
  final local = dt.toLocal();
  return DateFormat.jm().format(local);
}

class _MedicationTodayList extends ConsumerWidget {
  const _MedicationTodayList({required this.babyId});
  final String babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final async = ref.watch(medicationTodayProvider(babyId));

    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (doses) {
        if (doses.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Center(
              child: Text(
                l10n.medHistoryEmpty,
                style: AppTypography.bodyMedium(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: doses.map((d) => _DoseRow(dose: d, babyId: babyId)).toList(),
        );
      },
    );
  }
}

class _DoseRow extends ConsumerWidget {
  const _DoseRow({required this.dose, required this.babyId});
  final MedicationDose dose;
  final String babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();

    Widget? nextDoseLabel;
    if (dose.nextDoseAt != null) {
      final isOverdue = dose.nextDoseAt!.isBefore(now);
      nextDoseLabel = Text(
        isOverdue
            ? l10n.medNextDoseOverdue
            : l10n.medNextDoseAt(_fmtTime(dose.nextDoseAt!)),
        style: AppTypography.labelLarge(
          color: isOverdue ? scheme.error : AppColors.honey700,
        ),
      );
    }

    return Dismissible(
      key: ValueKey(dose.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: AppSpacing.md),
        color: scheme.error,
        child: Icon(Icons.delete_outline, color: scheme.onError),
      ),
      onDismissed: (_) async {
        await ref.read(medicationRepositoryProvider).softDelete(dose.id);
        ref.invalidate(medicationTodayProvider(babyId));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            SizedBox(
              width: 60,
              child: Text(
                _fmtTime(dose.givenAt),
                style: AppTypography.numeric(
                  size: 14,
                  weight: FontWeight.w500,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            const Icon(Icons.medication_outlined, size: 18),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${dose.drugName} ${dose.doseAmount % 1 == 0 ? dose.doseAmount.toInt() : dose.doseAmount}${dose.doseUnit}',
                    style: AppTypography.bodyMedium(color: scheme.onSurface),
                  ),
                  if (nextDoseLabel != null) nextDoseLabel,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
