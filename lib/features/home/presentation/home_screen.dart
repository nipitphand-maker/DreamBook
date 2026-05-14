import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/router/app_router.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/feed/data/feed_providers.dart';
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
        title: Text(l10n.appName),
        actions: [
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.sm),
              _TodayHeroCard(babyId: babyId),
              const SizedBox(height: AppSpacing.xs),
              const _CaregiverActivityPill(),
              const SizedBox(height: AppSpacing.md),
              _TodayTimelineRow(babyId: babyId),
              const SizedBox(height: AppSpacing.md),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: Text(
                      l10n.shareJustYou,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium(
                        color: AppColors.inkSecondary,
                      ),
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Stat(label: l10n.homeQuickLogFeed, value: feedOzText),
            _Stat(label: l10n.homeQuickLogDiaper, value: '0'),
            _Stat(label: l10n.homeQuickLogSleep, value: '0 hr'),
            _Stat(label: l10n.homeQuickLogPump, value: '0'),
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
          onTap: () {},
        ),
        _QuickLogButton(
          icon: Icons.baby_changing_station_outlined,
          label: l10n.homeQuickLogDiaper,
          onTap: () {},
        ),
        _QuickLogButton(
          icon: Icons.bedtime_outlined,
          label: l10n.homeQuickLogSleep,
          onTap: () {},
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
