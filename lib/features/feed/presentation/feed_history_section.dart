import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/unit_preferences_provider.dart';
import 'package:dreambook/core/services/unit_preferences.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/core/widgets/history_actions_menu.dart';
import 'package:dreambook/features/feed/data/feed_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _mlPerOz = 29.5735;

String _fmtVol(double oz, VolumeUnit unit) => unit == VolumeUnit.oz
    ? '${oz.toStringAsFixed(1)} oz'
    : '${(oz * _mlPerOz).round()} ml';

/// "Today's history" list shown at the bottom of [FeedScreen].
///
/// Lists today's non-deleted feeds for [babyId] in `started_at DESC` order
/// (freshest first). Each row's trailing menu (edit / delete) is gated by
/// the caregiver role via [HistoryActionsMenu] — admins always see both
/// actions, editors only on their own rows, read-only users see nothing.
class FeedHistorySection extends ConsumerWidget {
  const FeedHistorySection({super.key, required this.babyId});

  final String babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final unit = ref.watch(unitPreferencesProvider).volume;
    final feedsAsync = ref.watch(feedTodayProvider(babyId));

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
        feedsAsync.when(
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
          data: (feeds) {
            if (feeds.isEmpty) {
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
                for (final feed in feeds)
                  _FeedHistoryTile(
                    feed: feed,
                    unit: unit,
                    babyId: babyId,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _FeedHistoryTile extends ConsumerWidget {
  const _FeedHistoryTile({
    required this.feed,
    required this.unit,
    required this.babyId,
  });

  final Feed feed;
  final VolumeUnit unit;
  final String babyId;

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _title(BuildContext context) {
    if (feed.type == FeedType.breast) {
      final side = switch (feed.side) {
        FeedSide.left => context.l10n.feedSideLeft,
        FeedSide.right => context.l10n.feedSideRight,
        FeedSide.both => '',
        null => '',
      };
      return '${context.l10n.feedTypeBreast}${side.isEmpty ? '' : ' · $side'}';
    }
    final volume = feed.oz == null ? '?' : _fmtVol(feed.oz!, unit);
    return '${context.l10n.feedTypeBottle} · $volume';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return ListTile(
      key: Key('feed_history_${feed.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      leading: Icon(
        feed.type == FeedType.breast
            ? Icons.child_care_outlined
            : Icons.local_drink_outlined,
        color: AppColors.peach700,
      ),
      title: Text(_title(context)),
      subtitle: Text(
        '${_fmtTime(feed.startedAt)}${feed.note == null ? '' : ' · ${feed.note}'}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: HistoryActionsMenu(
        rowLoggedBy: feed.loggedBy,
        onEdit: () => _showEditSheet(context, ref),
        onDelete: () async {
          await ref
              .read(feedRepositoryProvider)
              .softDelete(feed.id, babyId: babyId);
        },
        confirmTitle: l10n.historyActionConfirmDeleteFeed,
        confirmBody: l10n.historyActionConfirmDeleteFeedBody,
      ),
    );
  }

  void _showEditSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FeedEditSheet(feed: feed, unit: unit),
    );
  }
}

/// Minimal edit sheet for a single Feed row. Lets the user adjust the time,
/// volume (bottle only), and the note — the same fields the original log
/// screen captured. Uses `FeedRepository.update` so version bumps + sync
/// state stay in lockstep with the rest of the app.
class _FeedEditSheet extends ConsumerStatefulWidget {
  const _FeedEditSheet({required this.feed, required this.unit});

  final Feed feed;
  final VolumeUnit unit;

  @override
  ConsumerState<_FeedEditSheet> createState() => _FeedEditSheetState();
}

class _FeedEditSheetState extends ConsumerState<_FeedEditSheet> {
  late DateTime _startedAt;
  late double _oz;
  late TextEditingController _notesCtrl;

  @override
  void initState() {
    super.initState();
    _startedAt = widget.feed.startedAt.toLocal();
    _oz = widget.feed.oz ?? 0;
    _notesCtrl = TextEditingController(text: widget.feed.note ?? '');
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
    final isBottle = widget.feed.type == FeedType.bottle;
    final next = widget.feed.copyWith(
      startedAt: _startedAt,
      oz: isBottle ? _oz : widget.feed.oz,
      note: note,
      clearNote: note == null,
    );
    try {
      await ref.read(feedRepositoryProvider).update(next);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(l10n.historyEditSaved)));
    } on ConcurrentUpdateException {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.historyEditConflict)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isBottle = widget.feed.type == FeedType.bottle;
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
              l10n.historyEditFeedTitle,
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
            if (isBottle) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filled(
                    onPressed: _oz <= 0
                        ? null
                        : () => setState(() => _oz = (_oz - 0.5).clamp(0.0, 12.0)),
                    icon: const Icon(Icons.remove),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Text(
                    _fmtVol(_oz, widget.unit),
                    style: AppTypography.statHero(color: AppColors.inkPrimary),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  IconButton.filled(
                    onPressed: _oz >= 12.0
                        ? null
                        : () => setState(() => _oz = (_oz + 0.5).clamp(0.0, 12.0)),
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
            ],
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
