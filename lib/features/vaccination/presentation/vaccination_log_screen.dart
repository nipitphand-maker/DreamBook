import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/vaccination/data/vaccination_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'add_vaccination_screen.dart';

/// Vaccination log — chronological list of shots for the current baby.
///
/// FAB opens [AddVaccinationScreen]. Long-press a tile to soft-delete.
class VaccinationLogScreen extends ConsumerWidget {
  const VaccinationLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final babyId = ref.watch(currentBabyIdProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.vaccinationTitle)),
      floatingActionButton: babyId == null
          ? null
          : FloatingActionButton(
              onPressed: () => _onAdd(context, ref, babyId),
              tooltip: l10n.vaccinationAddVaccine,
              child: const Icon(Icons.add),
            ),
      body: babyId == null
          ? const Center(child: Text('No baby profile.'))
          : ref.watch(vaccinationListProvider(babyId)).when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => Center(child: Text(l10n.errorGeneric)),
                data: (records) {
                  if (records.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Text(
                          l10n.vaccinationEmptyState,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyMedium(
                            color: AppColors.inkSecondary,
                          ),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    itemCount: records.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, thickness: 0.5),
                    itemBuilder: (_, i) => _VaccinationTile(record: records[i]),
                  );
                },
              ),
    );
  }

  Future<void> _onAdd(
    BuildContext context,
    WidgetRef ref,
    String babyId,
  ) async {
    await Navigator.of(context).push<VaccinationRecord>(
      MaterialPageRoute(
        builder: (_) => AddVaccinationScreen(babyId: babyId),
      ),
    );
    // Provider auto-rebuilds via invalidate() inside the repository.
  }
}

class _VaccinationTile extends ConsumerWidget {
  const _VaccinationTile({required this.record});

  final VaccinationRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final dateLabel = DateFormat.yMMMd().format(record.givenOn.toLocal());
    final subtitle = record.clinic;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      title: Text(
        record.vaccineName,
        style: AppTypography.titleLarge(color: AppColors.inkPrimary),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xxs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dateLabel,
              style: AppTypography.bodyMedium(color: AppColors.inkSecondary),
            ),
            if (subtitle != null && subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxs),
                child: Text(
                  subtitle,
                  style: AppTypography.bodyMedium(
                    color: AppColors.inkSecondary,
                  ),
                ),
              ),
          ],
        ),
      ),
      onLongPress: () => _confirmDelete(context, ref, l10n),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    AppLocalizations l10n,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.vaccinationDeleteConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(MaterialLocalizations.of(ctx).deleteButtonTooltip),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(vaccinationRepositoryProvider).softDelete(
          record.id,
          babyId: record.babyId,
        );
  }
}
