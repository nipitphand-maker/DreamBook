import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/families/family_provider.dart';
import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/router/app_router.dart';
import 'package:dreambook/core/sync/sync_lifecycle_controller.dart';
import 'package:dreambook/core/sync/sync_status_provider.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/features/baby/data/baby_repository.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/core/providers/unit_preferences_provider.dart';
import 'package:dreambook/core/services/unit_preferences.dart';
import 'package:dreambook/features/home/data/home_timeline_provider.dart';
import 'package:dreambook/features/sleep/data/sleep_repository.dart';
import 'package:dreambook/features/summary/data/summary_provider.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const double _mlPerOz = 29.5735;

String _fmtVol(double oz, VolumeUnit unit) => unit == VolumeUnit.oz
    ? '${oz.toStringAsFixed(1)} oz'
    : '${(oz * _mlPerOz).round()} ml';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final babyId = ref.watch(currentBabyIdProvider);
    final syncStatus = ref.watch(syncStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: BabySwitcherTitle(babyId: babyId),
        actions: [
          _SyncButton(syncStatus: syncStatus),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurface,
            ),
            icon: const Icon(Icons.group_add_outlined, size: 18),
            label: Text('+ ${l10n.shareTitle}'),
            onPressed: () => context.push(AppRoutes.caregivers),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(syncLifecycleControllerProvider).syncNow(),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Banners: family switcher, sync status, active sleep
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _FamilyBanner(),
                      _SyncStatusRow(syncStatus: syncStatus),
                      if (babyId != null) _ActiveSleepBanner(babyId: babyId),
                    ],
                  ),
                ),
              ),
              // Today's stat summary: Feed · Pump · Diaper · Sleep
              if (babyId != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
                  sliver: SliverToBoxAdapter(
                    child: _TodaySummaryStrip(babyId: babyId),
                  ),
                ),
              // Quick-log row — positioned between stats and timeline
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
                sliver: SliverToBoxAdapter(child: _QuickLogRow()),
              ),
              // Medication quick-action
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.xs, AppSpacing.md, 0),
                sliver: SliverToBoxAdapter(
                  child: _MedicationQuickAction(),
                ),
              ),
              // "Recent activity" label + "All →" button
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.xs),
                sliver: SliverToBoxAdapter(
                  child: _RecentActivityHeader(),
                ),
              ),
              // Timeline — last 5 events only
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                sliver: HomeTimelineSliver(babyId: babyId, maxItems: 5),
              ),
              const SliverToBoxAdapter(
                child: SizedBox(height: AppSpacing.lg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Today stat strip (horizontal 4-tile) ─────────────────────────────────

class _TodaySummaryStrip extends ConsumerWidget {
  const _TodaySummaryStrip({required this.babyId});
  final String babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(unitPreferencesProvider).volume;
    final async = ref.watch(dailySummaryProvider(babyId));

    return async.when(
      loading: () => const _StatStripSkeleton(),
      error: (_, __) => const SizedBox.shrink(),
      data: (s) {
        final scheme = Theme.of(context).colorScheme;
        return Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      icon: Icons.water_drop_outlined,
                      label: context.l10n.homeQuickLogFeed,
                      value: s.feedCount == 0 ? '—' : _fmtVol(s.feedOz, unit),
                      sub: s.feedCount == 0 ? null : '${s.feedCount}×',
                      color: AppColors.lavender700,
                      onTap: () => context.push(AppRoutes.feedNew),
                    ),
                  ),
                  Expanded(
                    child: _StatTile(
                      icon: Icons.compress_outlined,
                      label: context.l10n.homeQuickLogPump,
                      value: s.pumpCount == 0 ? '—' : _fmtVol(s.pumpOz, unit),
                      sub: s.pumpCount == 0 ? null : '${s.pumpCount}×',
                      color: AppColors.honey700,
                      onTap: () => context.push(AppRoutes.pumpNew),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      icon: Icons.baby_changing_station_outlined,
                      label: context.l10n.homeQuickLogDiaper,
                      value: s.diaperCount == 0 ? '—' : '${s.diaperCount}×',
                      color: AppColors.peach700,
                      onTap: () => context.push(AppRoutes.diaperNew),
                    ),
                  ),
                  Expanded(
                    child: _StatTile(
                      icon: Icons.bedtime_outlined,
                      label: context.l10n.homeQuickLogSleep,
                      value: s.sleepFormatted,
                      color: AppColors.sage700,
                      onTap: () => context.push(AppRoutes.sleep),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.sub,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 4),
              Text(
                value,
                style: AppTypography.numeric(
                    size: 15, weight: FontWeight.w800, color: scheme.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (sub != null)
                Text(
                  sub!,
                  style: AppTypography.labelLarge(
                      color: scheme.onSurface.withValues(alpha: 0.6)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              Text(
                label,
                style: AppTypography.labelLarge(
                    color: scheme.onSurface.withValues(alpha: 0.6)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatStripSkeleton extends StatelessWidget {
  const _StatStripSkeleton();

  @override
  Widget build(BuildContext context) {
    final cell = Expanded(
      child: Container(
        height: 70,
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        decoration: BoxDecoration(
          color: AppColors.neutralMuted.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
      ),
    );
    return Row(children: [cell, cell, cell, cell]);
  }
}

// ── Recent activity section header ─────────────────────────────────────────

class _RecentActivityHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          l10n.homeRecentActivity,
          style: AppTypography.labelLarge(color: scheme.onSurface)
              .copyWith(fontWeight: FontWeight.w700),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => context.push(AppRoutes.summary),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.homeViewAll,
                style: AppTypography.labelLarge(color: scheme.primary),
              ),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right, size: 16, color: scheme.primary),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Active sleep banner ────────────────────────────────────────────────────

class _ActiveSleepBanner extends ConsumerWidget {
  const _ActiveSleepBanner({required this.babyId});
  final String babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(sleepActiveProvider(babyId)).value;
    if (active == null) return const SizedBox.shrink();
    final diff = DateTime.now().difference(active.startedAt);
    final h = diff.inHours;
    final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final elapsed = h > 0 ? '${h}h ${m}m' : '${diff.inMinutes}m';
    return GestureDetector(
      onTap: () => context.push(AppRoutes.sleep),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.sage700.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(AppRadii.md),
        ),
        child: Row(
          children: [
            const Icon(Icons.bedtime_outlined,
                color: AppColors.sage700, size: 18),
            const SizedBox(width: AppSpacing.xs),
            Text(context.l10n.homeSleepingStatus(elapsed),
                style: AppTypography.labelLarge(color: AppColors.sage700)),
            const Spacer(),
            const Icon(Icons.chevron_right,
                color: AppColors.sage700, size: 16),
          ],
        ),
      ),
    );
  }
}

// ── Timeline ───────────────────────────────────────────────────────────────

/// The Home screen's recent activity feed, limited to [maxItems] entries.
///
/// Public (not `_`-prefixed) so widget tests can mount it standalone with
/// `homeTodayTimelineProvider` overrides.
class HomeTimelineSliver extends ConsumerWidget {
  const HomeTimelineSliver({super.key, required this.babyId, this.maxItems});
  final String? babyId;
  final int? maxItems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (babyId == null) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final async = ref.watch(homeTodayTimelineProvider(babyId!));
    return async.when(
      loading: () => const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (_, __) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          child: Center(
            child: Text(
              context.l10n.errorGeneric,
              style: AppTypography.bodyMedium(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6)),
            ),
          ),
        ),
      ),
      data: (allEntries) {
        if (allEntries.isEmpty) {
          return SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.xl),
              child: Center(
                child: Text(
                  context.l10n.homeTimelineEmpty,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6)),
                ),
              ),
            ),
          );
        }
        final unit = ref.watch(unitPreferencesProvider).volume;
        final timeFormat = ref.watch(unitPreferencesProvider).timeFormat;
        final entries = maxItems == null
            ? allEntries
            : allEntries.take(maxItems!).toList();
        return SliverList.separated(
          itemCount: entries.length,
          separatorBuilder: (_, __) =>
              const SizedBox(height: AppSpacing.xxs),
          itemBuilder: (_, i) => _TimelineRow(
            entry: entries[i],
            unit: unit,
            timeFormat: timeFormat,
          ),
        );
      },
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.entry,
    required this.unit,
    required this.timeFormat,
  });

  final HomeTimelineEntry entry;
  final VolumeUnit unit;
  final TimeFormat timeFormat;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final (icon, label) = switch (entry) {
      FeedTimelineEntry(:final feed) => (
          Icons.water_drop_outlined,
          feed.type == FeedType.breast
              ? l10n.homeTimelineFeedBreast
              : (feed.oz == null
                  ? l10n.homeTimelineFeedBottleNoVol
                  : l10n.homeTimelineFeedBottle(_fmtVol(feed.oz!, unit))),
        ),
      PumpTimelineEntry(:final session) => () {
          final total = session.leftOz + session.rightOz;
          return (
            Icons.compress_outlined,
            total > 0
                ? l10n.homeTimelinePumpWithVol(_fmtVol(total, unit))
                : l10n.homeTimelinePumpNoVol,
          );
        }(),
      DiaperTimelineEntry(:final diaper) => (
          Icons.baby_changing_station_outlined,
          switch (diaper.type) {
            DiaperType.pee => l10n.homeTimelineDiaperPee,
            DiaperType.poop => l10n.homeTimelineDiaperPoop,
            DiaperType.mixed => l10n.homeTimelineDiaperMixed,
            DiaperType.dry => l10n.homeTimelineDiaperDry,
          },
        ),
      SleepTimelineEntry(:final sleep) => (
          Icons.bedtime_outlined,
          sleep.endedAt == null
              ? l10n.homeTimelineSleepActive
              : l10n.homeTimelineSleepDuration(
                  _fmtDuration(sleep.durationMin ?? 0)),
        ),
      StashAddTimelineEntry(:final bottle) => (
          Icons.ac_unit_outlined,
          l10n.homeTimelineStashAdd(_fmtVol(bottle.oz, unit)),
        ),
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _navigateForEntry(context, entry),
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: ConstrainedBox(
          constraints:
              const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs, vertical: AppSpacing.xs),
            child: Row(
              children: [
                SizedBox(
                  width: 56,
                  child: Text(
                    _fmtTime(entry.timestamp, timeFormat),
                    style: AppTypography.numeric(
                      size: 14,
                      weight: FontWeight.w500,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
                Icon(icon, size: 18,
                    color: scheme.onSurface.withValues(alpha: 0.6)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    label,
                    style: AppTypography.bodyMedium(color: scheme.onSurface),
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 18,
                    color: scheme.onSurface.withValues(alpha: 0.6)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _navigateForEntry(BuildContext context, HomeTimelineEntry entry) {
  final (path, rowId) = switch (entry) {
    FeedTimelineEntry(:final feed) => (AppRoutes.feedNew, feed.id),
    PumpTimelineEntry(:final session) => (AppRoutes.pumpNew, session.id),
    DiaperTimelineEntry(:final diaper) => (AppRoutes.diaperNew, diaper.id),
    SleepTimelineEntry(:final sleep) => (AppRoutes.sleep, sleep.id),
    StashAddTimelineEntry(:final bottle) => (AppRoutes.stash, bottle.id),
  };
  context.push('$path?id=$rowId');
}

String _fmtTime(DateTime when, TimeFormat fmt) {
  final local = when.toLocal();
  if (fmt == TimeFormat.h24) {
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }
  final h = local.hour == 0
      ? 12
      : (local.hour > 12 ? local.hour - 12 : local.hour);
  final mm = local.minute.toString().padLeft(2, '0');
  final ampm = local.hour < 12 ? 'AM' : 'PM';
  return '$h:$mm $ampm';
}

String _fmtDuration(int minutes) {
  if (minutes <= 0) return '0m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h > 0 && m > 0) return '${h}h ${m}m';
  if (h > 0) return '${h}h';
  return '${m}m';
}

// ── Medication quick-action card ──────────────────────────────────────────

class _MedicationQuickAction extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.md),
        onTap: () => context.push(AppRoutes.medicationNew),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            children: [
              Icon(Icons.medication_outlined,
                  size: 20, color: scheme.onSecondaryContainer),
              const SizedBox(width: AppSpacing.sm),
              Text(
                l10n.medNavLabel,
                style: AppTypography.bodyMedium(
                    color: scheme.onSecondaryContainer),
              ),
              const Spacer(),
              Icon(Icons.chevron_right,
                  size: 18, color: scheme.onSecondaryContainer),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Quick-log row ──────────────────────────────────────────────────────────

class _QuickLogRow extends StatelessWidget {
  const _QuickLogRow();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: _QuickLogPill(
            icon: Icons.water_drop_outlined,
            label: l10n.homeQuickLogFeed,
            onTap: () => context.push(AppRoutes.feedNew),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: _QuickLogPill(
            icon: Icons.compress_outlined,
            label: l10n.homeQuickLogPump,
            onTap: () => context.push(AppRoutes.pumpNew),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: _QuickLogPill(
            icon: Icons.baby_changing_station_outlined,
            label: l10n.homeQuickLogDiaper,
            onTap: () => context.push(AppRoutes.diaperNew),
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: _QuickLogPill(
            icon: Icons.bedtime_outlined,
            label: l10n.homeQuickLogSleep,
            onTap: () => context.push(AppRoutes.sleep),
          ),
        ),
      ],
    );
  }
}

class _QuickLogPill extends StatelessWidget {
  const _QuickLogPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 88),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 28, color: scheme.primary),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodyMedium(color: scheme.onSurface),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Baby switcher AppBar title ─────────────────────────────────────────────

/// AppBar title showing the current baby's name with a chevron, tappable
/// to open the multi-baby switcher at [AppRoutes.babies].
class BabySwitcherTitle extends ConsumerWidget {
  const BabySwitcherTitle({super.key, required this.babyId});
  final String? babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    if (babyId == null) {
      return Text(l10n.appName);
    }
    final babies = ref.watch(_babiesListProvider).value;
    final baby = (babies == null || babies.isEmpty)
        ? null
        : babies.firstWhereOrNull((b) => b.id == babyId);
    final display = baby == null
        ? l10n.appName
        : (baby.nickname?.isNotEmpty == true ? baby.nickname! : baby.name);
    return InkWell(
      onTap: () => context.push(AppRoutes.babies),
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                display,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            const Icon(Icons.arrow_drop_down, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Sync button + status row ───────────────────────────────────────────────

class _SyncButton extends ConsumerWidget {
  const _SyncButton({required this.syncStatus});
  final SyncStatus syncStatus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    if (syncStatus.inFlight) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return IconButton(
      icon: const Icon(Icons.sync),
      tooltip: l10n.syncButtonTooltip,
      onPressed: () => ref.read(syncLifecycleControllerProvider).syncNow(),
    );
  }
}

class _SyncStatusRow extends StatelessWidget {
  const _SyncStatusRow({required this.syncStatus});
  final SyncStatus syncStatus;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    if (syncStatus.realtimeDegraded) {
      return Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
        child: Row(
          children: [
            const Icon(Icons.wifi_off, size: 12, color: AppColors.peach700),
            const SizedBox(width: 4),
            Text(
              l10n.syncStatusRealtimeDegraded,
              style: AppTypography.bodyMedium(color: AppColors.peach700),
            ),
          ],
        ),
      );
    }
    if (syncStatus.lastError != null && !syncStatus.inFlight) {
      return Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
        child: Row(
          children: [
            const Icon(Icons.sync_problem,
                size: 12, color: AppColors.peach700),
            const SizedBox(width: 4),
            Text(
              l10n.syncStatusError,
              style: AppTypography.bodyMedium(color: AppColors.peach700),
            ),
          ],
        ),
      );
    }
    final lastSynced = syncStatus.lastSyncedAt;
    if (syncStatus.inFlight || lastSynced == null) {
      return const SizedBox.shrink();
    }
    final diff = DateTime.now().toUtc().difference(lastSynced);
    final label = diff.inMinutes < 1
        ? l10n.syncStatusSyncedJustNow
        : l10n.syncStatusSyncedMinutes(diff.inMinutes);
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline,
              size: 12,
              color: scheme.onSurface.withValues(alpha: 0.6)),
          const SizedBox(width: 4),
          Text(label,
              style: AppTypography.bodyMedium(
                  color: scheme.onSurface.withValues(alpha: 0.6))),
        ],
      ),
    );
  }
}

// ── Family banner ──────────────────────────────────────────────────────────

class _FamilyBanner extends ConsumerWidget {
  const _FamilyBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final families = ref.watch(familyListProvider);
    if (families.length <= 1) return const SizedBox.shrink();

    final activeId = ref.watch(familyRepositoryProvider).activeId();
    final active =
        families.firstWhereOrNull((f) => f.id == activeId) ?? families.first;

    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: InkWell(
        onTap: () => context.push(AppRoutes.families),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xxs,
          ),
          child: Text(
            context.l10n.homeFamilyBanner(active.label),
            style: AppTypography.labelLarge(
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

// ── Providers ──────────────────────────────────────────────────────────────

final _babiesListProvider = FutureProvider<List<Baby>>((ref) async {
  ref.watch(appDatabaseProvider);
  return ref.read(babyRepositoryProvider).list();
});
