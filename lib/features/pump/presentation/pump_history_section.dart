import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/unit_preferences_provider.dart';
import 'package:dreambook/core/services/unit_preferences.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/core/widgets/history_actions_menu.dart';
import 'package:dreambook/features/pump/data/pump_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _mlPerOz = 29.5735;

String _fmtVol(double oz, VolumeUnit unit) => unit == VolumeUnit.oz
    ? '${oz.toStringAsFixed(1)} oz'
    : '${(oz * _mlPerOz).round()} ml';

/// "Today's history" section for the Pump screen — see [FeedHistorySection]
/// for the design rationale. Lists `started_at DESC`, edits adjust time +
/// L/R oz + note, deletes are soft (sync-safe).
class PumpHistorySection extends ConsumerWidget {
  const PumpHistorySection({super.key, required this.babyId});

  final String babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final unit = ref.watch(unitPreferencesProvider).volume;
    final sessionsAsync = ref.watch(pumpTodayProvider(babyId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xs,
            vertical: AppSpacing.xs,
          ),
          child: Text(
            l10n.historyRecentToday,
            style: AppTypography.labelLarge(color: AppColors.inkSecondary),
          ),
        ),
        sessionsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              l10n.errorGeneric,
              style: AppTypography.bodyMedium(color: AppColors.inkSecondary),
            ),
          ),
          data: (sessions) {
            if (sessions.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.sm,
                  horizontal: AppSpacing.xs,
                ),
                child: Text(
                  l10n.historyEmpty,
                  style: AppTypography.bodyMedium(color: AppColors.inkSecondary),
                ),
              );
            }
            return Column(
              children: [
                for (final s in sessions)
                  _PumpHistoryTile(session: s, unit: unit, babyId: babyId),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _PumpHistoryTile extends ConsumerWidget {
  const _PumpHistoryTile({
    required this.session,
    required this.unit,
    required this.babyId,
  });

  final PumpSession session;
  final VolumeUnit unit;
  final String babyId;

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final total = session.leftOz + session.rightOz;
    final subtitle = '${_fmtTime(session.startedAt.toLocal())} · '
        '${_fmtVol(total, unit)}'
        '${session.durationMin == null ? '' : ' · ${session.durationMin}m'}';
    return ListTile(
      key: Key('pump_history_${session.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      leading: const Icon(Icons.compress_outlined, color: AppColors.peach700),
      title: Text(
        'L ${_fmtVol(session.leftOz, unit)} · R ${_fmtVol(session.rightOz, unit)}',
      ),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: HistoryActionsMenu(
        rowLoggedBy: session.loggedBy,
        onEdit: () => _showEditSheet(context, ref),
        onDelete: () async {
          await ref
              .read(pumpRepositoryProvider)
              .softDelete(session.id, babyId: babyId);
        },
        confirmTitle: l10n.historyActionConfirmDeletePump,
        confirmBody: l10n.historyActionConfirmDeletePumpBody,
      ),
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PumpEditSheet(session: session, unit: unit),
    );
  }
}

class _PumpEditSheet extends ConsumerStatefulWidget {
  const _PumpEditSheet({required this.session, required this.unit});

  final PumpSession session;
  final VolumeUnit unit;

  @override
  ConsumerState<_PumpEditSheet> createState() => _PumpEditSheetState();
}

class _PumpEditSheetState extends ConsumerState<_PumpEditSheet> {
  late DateTime _startedAt;
  late double _leftOz;
  late double _rightOz;
  late TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _startedAt = widget.session.startedAt.toLocal();
    _leftOz = widget.session.leftOz;
    _rightOz = widget.session.rightOz;
    _notesCtrl = TextEditingController(text: widget.session.note ?? '');
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickStartedAt() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _startedAt,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startedAt),
    );
    if (time == null) return;
    final picked =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!picked.isAfter(now)) setState(() => _startedAt = picked);
  }

  String _fmtDateTime(DateTime dt) {
    final date = '${dt.day}/${dt.month}/${dt.year}';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$date  $h:$m';
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final note = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();
    final next = widget.session.copyWith(
      startedAt: _startedAt,
      leftOz: _leftOz,
      rightOz: _rightOz,
      note: note,
    );
    try {
      await ref.read(pumpRepositoryProvider).update(next);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(l10n.historyEditSaved)));
    } on StateError {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.historyEditConflict)),
      );
    }
  }

  Widget _ozStepper({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
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
          onPressed: value <= 0
              ? null
              : () => onChanged(
                  double.parse((value - 0.5).clamp(0.0, 16.0).toStringAsFixed(2))),
          icon: const Icon(Icons.remove),
        ),
        const SizedBox(width: AppSpacing.sm),
        SizedBox(
          width: 68,
          child: Text(
            _fmtVol(value, widget.unit),
            style: AppTypography.numeric(size: 18, weight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        IconButton.filled(
          onPressed: value >= 16.0
              ? null
              : () => onChanged(
                  double.parse((value + 0.5).clamp(0.0, 16.0).toStringAsFixed(2))),
          icon: const Icon(Icons.add),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SafeArea(
      child: Padding(
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
              l10n.historyEditPumpTitle,
              style: AppTypography.titleLarge(color: AppColors.inkPrimary),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                const Icon(Icons.schedule, size: 18,
                    color: AppColors.inkSecondary),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '${l10n.historyFieldStartedAt}: ',
                  style: AppTypography.bodyMedium(color: AppColors.inkSecondary),
                ),
                GestureDetector(
                  onTap: _pickStartedAt,
                  child: Text(
                    _fmtDateTime(_startedAt),
                    style:
                        AppTypography.bodyMedium(color: AppColors.lavender700)
                            .copyWith(decoration: TextDecoration.underline),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _ozStepper(
              label: l10n.historyFieldLeftOz,
              value: _leftOz,
              onChanged: (v) => setState(() => _leftOz = v),
            ),
            const SizedBox(height: AppSpacing.xs),
            _ozStepper(
              label: l10n.historyFieldRightOz,
              value: _rightOz,
              onChanged: (v) => setState(() => _rightOz = v),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _notesCtrl,
              maxLines: 2,
              maxLength: 240,
              decoration: InputDecoration(labelText: l10n.historyFieldNote),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: _save, child: Text(l10n.actionSave)),
          ],
        ),
      ),
    );
  }
}
