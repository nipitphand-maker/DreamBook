import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/features/caregivers/data/current_caregiver_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Trailing actions menu for "recent activity" list rows.
///
/// Shows an overflow icon (`⋯`) which opens a popup with Edit + Delete.
/// Visibility is gated by the current caregiver's role (see
/// [canEditRow] in `current_caregiver_provider.dart`):
/// - read-only → returns `SizedBox.shrink()` (no actions, list informational)
/// - editor → actions only for rows the device authored (or legacy rows with
///   `logged_by == null`)
/// - admin → actions on every row
///
/// The widget never deletes by itself — [onDelete] is called only AFTER the
/// user confirms in the dialog (copy localised via [confirmTitle] /
/// [confirmBody]). Repository soft-delete keeps the sync state intact.
class HistoryActionsMenu extends ConsumerWidget {
  const HistoryActionsMenu({
    super.key,
    required this.rowLoggedBy,
    required this.onEdit,
    required this.onDelete,
    required this.confirmTitle,
    required this.confirmBody,
  });

  /// `logged_by` column for this row — caregiver id of the original author,
  /// or null for legacy rows.
  final String? rowLoggedBy;

  /// Called when the user picks "Edit" from the menu.
  final VoidCallback onEdit;

  /// Called when the user picks "Delete" AND confirms the dialog.
  final Future<void> Function() onDelete;

  /// Title for the delete-confirmation dialog (e.g. "Delete this feed?").
  final String confirmTitle;

  /// Body for the delete-confirmation dialog.
  final String confirmBody;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(currentCaregiverRoleProvider);
    final selfId = ref.watch(currentCaregiverIdProvider);
    final allowed = canEditRow(
      role: role,
      rowLoggedBy: rowLoggedBy,
      selfCaregiverId: selfId,
    );
    if (!allowed) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      key: const Key('history_actions_menu'),
      icon: const Icon(
        Icons.more_horiz,
        color: AppColors.inkSecondary,
        size: 20,
      ),
      tooltip: context.l10n.historyActionsMenu,
      onSelected: (value) async {
        switch (value) {
          case 'edit':
            onEdit();
          case 'delete':
            final confirmed = await _confirmDelete(context);
            if (confirmed == true) {
              await onDelete();
            }
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          key: const Key('history_actions_edit'),
          value: 'edit',
          child: Row(
            children: [
              const Icon(Icons.edit_outlined, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Text(context.l10n.historyActionEdit),
            ],
          ),
        ),
        PopupMenuItem(
          key: const Key('history_actions_delete'),
          value: 'delete',
          child: Row(
            children: [
              const Icon(
                Icons.delete_outline,
                size: 18,
                color: AppColors.lightError,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                context.l10n.historyActionDelete,
                style: const TextStyle(color: AppColors.lightError),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(confirmTitle),
          content: Text(confirmBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(context.l10n.actionCancel),
            ),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.lightError),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(context.l10n.historyActionDelete),
            ),
          ],
        ),
      );
}
