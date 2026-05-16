import 'package:dreambook/core/data/milestone_catalog.dart';
import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/models/milestone_achievement.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/milestone/data/milestone_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

final _kAgeGroups = [
  (minM: 1, maxM: 3),
  (minM: 4, maxM: 6),
  (minM: 7, maxM: 9),
  (minM: 10, maxM: 12),
  (minM: 13, maxM: 18),
  (minM: 19, maxM: 24),
];

class MilestoneScreen extends ConsumerWidget {
  const MilestoneScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final babyId = ref.watch(currentBabyIdProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.milestonesTitle)),
      body: babyId == null
          ? Center(child: Text(l10n.errorNoBabyProfile))
          : ref.watch(milestoneAchievementsProvider(babyId)).when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (_, __) =>
                    Center(child: Text(l10n.errorGeneric)),
                data: (achievements) => _MilestoneList(
                  babyId: babyId,
                  achievements: achievements,
                ),
              ),
    );
  }
}

class _MilestoneList extends ConsumerWidget {
  const _MilestoneList({
    required this.babyId,
    required this.achievements,
  });

  final String babyId;
  final List<MilestoneAchievement> achievements;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final achievedById = {
      for (final a in achievements) a.milestoneId: a,
    };

    final groupLabels = [
      l10n.milestoneAgeGroup0,
      l10n.milestoneAgeGroup1,
      l10n.milestoneAgeGroup2,
      l10n.milestoneAgeGroup3,
      l10n.milestoneAgeGroup4,
      l10n.milestoneAgeGroup5,
    ];

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      itemCount: _kAgeGroups.length,
      itemBuilder: (context, groupIndex) {
        final group = _kAgeGroups[groupIndex];
        final milestones = kMilestoneCatalog
            .where(
              (m) =>
                  m.minMonths >= group.minM && m.maxMonths <= group.maxM,
            )
            .toList();

        if (milestones.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Text(
                groupLabels[groupIndex],
                style: AppTypography.labelLarge(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ).copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            ...milestones.map(
              (def) => _MilestoneTile(
                def: def,
                achievement: achievedById[def.id],
                babyId: babyId,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MilestoneTile extends ConsumerWidget {
  const _MilestoneTile({
    required this.def,
    required this.achievement,
    required this.babyId,
  });

  final MilestoneDef def;
  final MilestoneAchievement? achievement;
  final String babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isChecked = achievement != null;
    final locale = Localizations.localeOf(context).languageCode;
    final label = locale == 'th' ? def.labelTh : def.labelEn;

    return CheckboxListTile(
      value: isChecked,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xxs,
      ),
      title: Text(
        label,
        style: AppTypography.bodyMedium(
          color: isChecked
              ? AppColors.inkSecondary
              : AppColors.inkPrimary,
        ),
      ),
      subtitle: isChecked
          ? Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: _AchievedChip(date: achievement!.achievedOn),
            )
          : null,
      onChanged: (_) => isChecked
          ? _confirmUnmark(context, ref)
          : _pickDateAndMark(context, ref),
    );
  }

  Future<void> _pickDateAndMark(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 730)),
      lastDate: now,
      helpText: l10n.milestoneMarkDoneTitle,
    );
    if (picked == null || !context.mounted) return;

    final achieved = MilestoneAchievement(
      id: _uuid.v4(),
      babyId: babyId,
      milestoneId: def.id,
      achievedOn: DateTime(picked.year, picked.month, picked.day),
      version: 1,
      updatedAt: DateTime.now().toUtc(),
    );
    await ref.read(milestoneRepositoryProvider).markAchieved(achieved);
    ref.invalidate(milestoneAchievementsProvider(babyId));
  }

  Future<void> _confirmUnmark(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.milestoneUnmarkTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.milestoneUnmarkConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await ref
        .read(milestoneRepositoryProvider)
        .unmark(achievement!.id);
    ref.invalidate(milestoneAchievementsProvider(babyId));
  }
}

class _AchievedChip extends StatelessWidget {
  const _AchievedChip({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = DateFormat.yMMMd().format(date.toLocal());
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_outline, size: 14, color: scheme.primary),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          label,
          style: AppTypography.labelLarge(color: scheme.primary),
        ),
      ],
    );
  }
}
