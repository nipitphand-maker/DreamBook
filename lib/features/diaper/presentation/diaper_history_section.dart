import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/core/widgets/history_actions_menu.dart';
import 'package:dreambook/features/diaper/data/diaper_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Today's history" section for the Diaper screen — see
/// [FeedHistorySection] for the shared design rationale.
class DiaperHistorySection extends ConsumerWidget {
  const DiaperHistorySection({super.key, required this.babyId});

  final String babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final entriesAsync = ref.watch(diaperTodayProvider(babyId));

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
        entriesAsync.when(
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
          data: (entries) {
            if (entries.isEmpty) {
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
                for (final d in entries)
                  _DiaperHistoryTile(diaper: d, babyId: babyId),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _DiaperHistoryTile extends ConsumerWidget {
  const _DiaperHistoryTile({required this.diaper, required this.babyId});

  final Diaper diaper;
  final String babyId;

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _typeLabel(BuildContext context) => switch (diaper.type) {
        DiaperType.pee => context.l10n.diaperPee,
        DiaperType.poop => context.l10n.diaperPoop,
        DiaperType.mixed => context.l10n.diaperMixed,
        DiaperType.dry => context.l10n.diaperDry,
      };

  IconData _typeIcon() => switch (diaper.type) {
        DiaperType.pee => Icons.water_drop_outlined,
        DiaperType.poop => Icons.circle,
        DiaperType.mixed => Icons.water_drop,
        DiaperType.dry => Icons.do_not_disturb_alt_outlined,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return ListTile(
      key: Key('diaper_history_${diaper.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      leading: Icon(_typeIcon(), color: AppColors.honey700),
      title: Text(_typeLabel(context)),
      subtitle: Text(
        '${_fmtTime(diaper.occurredAt.toLocal())}${diaper.note == null ? '' : ' · ${diaper.note}'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: HistoryActionsMenu(
        rowLoggedBy: diaper.loggedBy,
        onEdit: () => _showEditSheet(context, ref),
        onDelete: () async {
          await ref
              .read(diaperRepositoryProvider)
              .softDelete(diaper.id, babyId: babyId);
        },
        confirmTitle: l10n.historyActionConfirmDeleteDiaper,
        confirmBody: l10n.historyActionConfirmDeleteDiaperBody,
      ),
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _DiaperEditSheet(diaper: diaper),
    );
  }
}

class _DiaperEditSheet extends ConsumerStatefulWidget {
  const _DiaperEditSheet({required this.diaper});

  final Diaper diaper;

  @override
  ConsumerState<_DiaperEditSheet> createState() => _DiaperEditSheetState();
}

class _DiaperEditSheetState extends ConsumerState<_DiaperEditSheet> {
  late DiaperType _type;
  late DateTime _occurredAt;
  late TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _type = widget.diaper.type;
    _occurredAt = widget.diaper.occurredAt.toLocal();
    _notesCtrl = TextEditingController(text: widget.diaper.note ?? '');
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickOccurredAt() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: now.subtract(const Duration(days: 30)),
      lastDate: now,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (time == null) return;
    final picked =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!picked.isAfter(now)) setState(() => _occurredAt = picked);
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
    final next = widget.diaper.copyWith(
      type: _type,
      occurredAt: _occurredAt,
      note: note,
      clearNote: note == null,
    );
    try {
      await ref.read(diaperRepositoryProvider).update(next);
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
              l10n.historyEditDiaperTitle,
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
                  onTap: _pickOccurredAt,
                  child: Text(
                    _fmtDateTime(_occurredAt),
                    style:
                        AppTypography.bodyMedium(color: AppColors.lavender700)
                            .copyWith(decoration: TextDecoration.underline),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<DiaperType>(
              segments: [
                ButtonSegment(
                  value: DiaperType.pee,
                  label: Text(l10n.diaperPee),
                ),
                ButtonSegment(
                  value: DiaperType.poop,
                  label: Text(l10n.diaperPoop),
                ),
                ButtonSegment(
                  value: DiaperType.mixed,
                  label: Text(l10n.diaperMixed),
                ),
                ButtonSegment(
                  value: DiaperType.dry,
                  label: Text(l10n.diaperDry),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
              showSelectedIcon: false,
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
