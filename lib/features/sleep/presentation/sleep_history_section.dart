import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/core/widgets/history_actions_menu.dart';
import 'package:dreambook/features/sleep/data/sleep_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Today's history" section for the Sleep screen — see
/// [FeedHistorySection] for the shared design rationale.
class SleepHistorySection extends ConsumerWidget {
  const SleepHistorySection({super.key, required this.babyId});

  final String babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final sleepsAsync = ref.watch(sleepTodayProvider(babyId));

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
        sleepsAsync.when(
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
          data: (sleeps) {
            if (sleeps.isEmpty) {
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
                for (final s in sleeps)
                  _SleepHistoryTile(sleep: s, babyId: babyId),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SleepHistoryTile extends ConsumerWidget {
  const _SleepHistoryTile({required this.sleep, required this.babyId});

  final Sleep sleep;
  final String babyId;

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _fmtDuration(int? min) {
    if (min == null) return '…';
    final h = min ~/ 60;
    final m = min % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final ended = sleep.endedAt;
    final timeRange = ended == null
        ? '${_fmtTime(sleep.startedAt.toLocal())} → …'
        : '${_fmtTime(sleep.startedAt.toLocal())} → ${_fmtTime(ended.toLocal())}';
    return ListTile(
      key: Key('sleep_history_${sleep.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      leading: const Icon(Icons.bedtime_outlined, color: AppColors.sage700),
      title: Text(_fmtDuration(sleep.durationMin)),
      subtitle: Text(
        '$timeRange${sleep.note == null ? '' : ' · ${sleep.note}'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: HistoryActionsMenu(
        rowLoggedBy: sleep.loggedBy,
        onEdit: () => _showEditSheet(context, ref),
        onDelete: () async {
          await ref
              .read(sleepRepositoryProvider)
              .softDelete(sleep.id, babyId: babyId);
        },
        confirmTitle: l10n.historyActionConfirmDeleteSleep,
        confirmBody: l10n.historyActionConfirmDeleteSleepBody,
      ),
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SleepEditSheet(sleep: sleep),
    );
  }
}

class _SleepEditSheet extends ConsumerStatefulWidget {
  const _SleepEditSheet({required this.sleep});

  final Sleep sleep;

  @override
  ConsumerState<_SleepEditSheet> createState() => _SleepEditSheetState();
}

class _SleepEditSheetState extends ConsumerState<_SleepEditSheet> {
  late DateTime _startedAt;
  late DateTime? _endedAt;
  late TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _startedAt = widget.sleep.startedAt.toLocal();
    _endedAt = widget.sleep.endedAt?.toLocal();
    _notesCtrl = TextEditingController(text: widget.sleep.note ?? '');
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

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

  String _fmtDateTime(DateTime dt) {
    final date = '${dt.day}/${dt.month}/${dt.year}';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$date  $h:$m';
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    if (_endedAt != null && !_endedAt!.isAfter(_startedAt)) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.sleepEndBeforeStart)),
      );
      return;
    }
    final note = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();
    final next = widget.sleep.copyWith(
      startedAt: _startedAt,
      endedAt: _endedAt,
      clearEndedAt: _endedAt == null,
      note: note,
      clearNote: note == null,
    );
    try {
      await ref.read(sleepRepositoryProvider).update(next);
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
              l10n.historyEditSleepTitle,
              style: AppTypography.titleLarge(color: AppColors.inkPrimary),
            ),
            const SizedBox(height: AppSpacing.md),
            InkWell(
              onTap: () => _pickDateTime(
                current: _startedAt,
                onPicked: (d) => setState(() => _startedAt = d),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Text(
                      l10n.historyFieldStartedAt,
                      style: AppTypography.bodyMedium(
                          color: AppColors.inkSecondary),
                    ),
                    const Spacer(),
                    Text(
                      _fmtDateTime(_startedAt),
                      style: AppTypography.numeric(size: 14),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            InkWell(
              onTap: () => _pickDateTime(
                current: _endedAt ?? DateTime.now(),
                onPicked: (d) => setState(() => _endedAt = d),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Row(
                  children: [
                    Text(
                      l10n.historyFieldEndedAt,
                      style: AppTypography.bodyMedium(
                          color: AppColors.inkSecondary),
                    ),
                    const Spacer(),
                    Text(
                      _endedAt == null ? '—' : _fmtDateTime(_endedAt!),
                      style: AppTypography.numeric(size: 14),
                    ),
                  ],
                ),
              ),
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
