import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/router/app_router.dart';
import 'package:dreambook/core/sync/sync_lifecycle_controller.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/features/baby/data/baby_repository.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/diaper/data/diaper_repository.dart';
import 'package:dreambook/features/feed/data/feed_providers.dart';
import 'package:dreambook/features/pump/data/pump_providers.dart';
import 'package:dreambook/features/sleep/data/sleep_repository.dart';
import 'package:dreambook/features/stash/data/stash_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final babyId = ref.watch(currentBabyIdProvider);

    return Scaffold(
      appBar: AppBar(
        title: _BabySwitcherTitle(babyId: babyId),
        actions: [
          IconButton(
            tooltip: 'Daily Summary',
            icon: const Icon(Icons.bar_chart_outlined),
            onPressed: () => context.go(AppRoutes.summary),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go(AppRoutes.settings),
          ),
          IconButton(
            tooltip: l10n.shareInviteCta,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: () => context.go(AppRoutes.shareInvite),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(syncLifecycleControllerProvider).syncNow(),
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(minHeight: constraints.maxHeight),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: AppSpacing.sm),
                      _TodayHeroCard(babyId: babyId),
                      const SizedBox(height: AppSpacing.xs),
                      const _CaregiverActivityPill(),
                      if (babyId != null) _ActiveSleepBanner(babyId: babyId),
                      if (babyId != null) _StashSummaryCard(babyId: babyId),
                      const SizedBox(height: AppSpacing.md),
                      _TodayTimelineRow(babyId: babyId),
                      if (babyId != null) _LastPumpChip(babyId: babyId),
                      const SizedBox(height: AppSpacing.md),
                      Expanded(
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  l10n.shareJustYou,
                                  textAlign: TextAlign.center,
                                  style: AppTypography.bodyMedium(
                                    color: AppColors.inkSecondary,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xs),
                                TextButton(
                                  onPressed: () =>
                                      context.go(AppRoutes.shareClaim),
                                  child: Text(l10n.joinHaveCode),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const _QuickLogGrid(),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TodayHeroCard extends ConsumerWidget {
  const _TodayHeroCard({required this.babyId});
  final String? babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    final feedOzText = babyId == null
        ? '—'
        : ref.watch(feedOzTodayProvider(babyId!)).when(
              loading: () => '—',
              error: (_, __) => '—',
              data: (oz) => '${oz.toStringAsFixed(1)} oz',
            );

    final pumpCountText = babyId == null
        ? '—'
        : ref.watch(pumpCountTodayProvider(babyId!)).when(
              loading: () => '—',
              error: (_, __) => '—',
              data: (n) => '$n',
            );

    final diaperCountText = babyId == null
        ? '—'
        : ref.watch(diaperCountTodayProvider(babyId!)).when(
              loading: () => '—',
              error: (_, __) => '—',
              data: (n) => '$n',
            );

    final sleepMinText = babyId == null
        ? '—'
        : ref.watch(sleepMinutesTodayProvider(babyId!)).when(
              loading: () => '—',
              error: (_, __) => '—',
              data: (min) {
                if (min == 0) return '0 hr';
                final h = min ~/ 60;
                final m = min % 60;
                return h > 0 ? '${h}h ${m}m' : '${m}m';
              },
            );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Stat(label: l10n.homeQuickLogFeed, value: feedOzText),
            _Stat(label: l10n.homeQuickLogDiaper, value: diaperCountText),
            _Stat(label: l10n.homeQuickLogSleep, value: sleepMinText),
            _Stat(label: l10n.homeQuickLogPump, value: pumpCountText),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          style: AppTypography.numeric(
            size: 20,
            weight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          label,
          style: AppTypography.labelLarge(
            color: scheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

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
      onTap: () => context.go(AppRoutes.sleep),
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
            Text('Sleeping · $elapsed',
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

class _CaregiverActivityPill extends StatelessWidget {
  const _CaregiverActivityPill();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          const Icon(Icons.people_outline,
              size: 16, color: AppColors.inkSecondary),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'Logged by you',
            style: AppTypography.labelLarge(color: AppColors.inkSecondary),
          ),
        ],
      ),
    );
  }
}

class _StashSummaryCard extends ConsumerWidget {
  const _StashSummaryCard({required this.babyId});
  final String babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totalOz = ref.watch(stashTotalOzProvider(babyId)).value ?? 0.0;
    final oldest = ref.watch(stashOldestProvider(babyId)).value;
    if (totalOz <= 0) return const SizedBox.shrink();

    String subtitle = '${totalOz.toStringAsFixed(1)} oz in stash';
    if (oldest != null) {
      final days = DateTime.now().difference(oldest.pumpedAt).inDays;
      subtitle += ' · oldest ${days}d';
    }

    return Card(
      child: ListTile(
        leading: const Icon(Icons.ac_unit, color: AppColors.lavender700),
        title: const Text('Freezer Stash'),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.go(AppRoutes.stash),
      ),
    );
  }
}

class _TodayTimelineRow extends ConsumerWidget {
  const _TodayTimelineRow({required this.babyId});
  final String? babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (babyId == null) return const SizedBox.shrink();

    final feedsAsync = ref.watch(feedRecentTodayProvider(babyId!));
    final feeds = feedsAsync.value ?? const <Feed>[];
    if (feeds.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        itemCount: feeds.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (_, i) => _FeedChip(feed: feeds[i]),
      ),
    );
  }
}

class _FeedChip extends StatelessWidget {
  const _FeedChip({required this.feed});
  final Feed feed;

  String _relativeTime(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _label() {
    final t = _relativeTime(feed.startedAt);
    if (feed.type == FeedType.breast) {
      return 'Feed · breast · $t';
    }
    final oz = feed.oz?.toStringAsFixed(1) ?? '?';
    return 'Feed · $oz oz · $t';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.neutralMuted,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(
        children: [
          const Icon(Icons.water_drop_outlined,
              size: 14, color: AppColors.inkSecondary),
          const SizedBox(width: AppSpacing.xs),
          Text(_label(),
              style: AppTypography.labelLarge(color: AppColors.inkPrimary)),
        ],
      ),
    );
  }
}

class _LastPumpChip extends ConsumerWidget {
  const _LastPumpChip({required this.babyId});
  final String babyId;

  String _label(PumpSession s) {
    final diff = DateTime.now().difference(s.startedAt);
    final timeStr = diff.inMinutes < 60
        ? '${diff.inMinutes}m ago'
        : '${diff.inHours}h ago';
    final total = s.leftOz + s.rightOz;
    final ozStr = total > 0 ? ' · ${total.toStringAsFixed(1)} oz' : '';
    return 'Pump · $timeStr$ozStr';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(lastPumpTodayProvider(babyId)).value;
    if (session == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          const Icon(Icons.compress_outlined,
              size: 14, color: AppColors.inkSecondary),
          const SizedBox(width: AppSpacing.xs),
          Text(_label(session),
              style: AppTypography.labelLarge(color: AppColors.inkPrimary)),
        ],
      ),
    );
  }
}

class _QuickLogGrid extends StatelessWidget {
  const _QuickLogGrid();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _QuickLogButton(
          icon: Icons.water_drop_outlined,
          label: l10n.homeQuickLogFeed,
          onTap: () => context.go(AppRoutes.feedNew),
        ),
        _QuickLogButton(
          icon: Icons.compress_outlined,
          label: l10n.homeQuickLogPump,
          onTap: () => context.go(AppRoutes.pumpNew),
        ),
        _QuickLogButton(
          icon: Icons.baby_changing_station_outlined,
          label: l10n.homeQuickLogDiaper,
          onTap: () => context.go(AppRoutes.diaperNew),
        ),
        _QuickLogButton(
          icon: Icons.bedtime_outlined,
          label: l10n.homeQuickLogSleep,
          onTap: () => context.go(AppRoutes.sleep),
        ),
      ],
    );
  }
}

class _QuickLogButton extends StatelessWidget {
  const _QuickLogButton({
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
          constraints: const BoxConstraints(minHeight: AppSpacing.quickLogButton),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 28, color: scheme.primary),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  label,
                  style: AppTypography.titleLarge(color: scheme.onSurface),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// AppBar title that shows the current baby's name with a chevron, tappable
/// to open the multi-baby switcher at [AppRoutes.babies].
///
/// Falls back to the app name when no baby is selected yet (e.g. before the
/// onboarding insert resolves).
class _BabySwitcherTitle extends ConsumerWidget {
  const _BabySwitcherTitle({required this.babyId});
  final String? babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    if (babyId == null) {
      return Text(l10n.appName);
    }
    final babies = ref.watch(_babiesListProvider).value;
    final baby = babies?.firstWhere(
      (b) => b.id == babyId,
      orElse: () => babies.first,
    );
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

/// Async list of all active babies (kept private to the home screen — the
/// switcher reads the repo directly).
final _babiesListProvider = FutureProvider<List<Baby>>((ref) async {
  return ref.read(babyRepositoryProvider).list();
});
