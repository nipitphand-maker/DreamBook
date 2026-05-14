import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/router/app_router.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/core/widgets/premium_gate.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/feed/data/feed_repository.dart' show feedTodayProvider;
import 'package:dreambook/features/summary/data/summary_provider.dart';
import 'package:dreambook/features/summary/presentation/feed_sparkline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Today's aggregated daily summary screen.
///
/// Route: [AppRoutes.summary] → `/summary`.
class DailySummaryScreen extends ConsumerWidget {
  const DailySummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final babyId = ref.watch(currentBabyIdProvider);
    final now = DateTime.now();
    final dateLabel = DateFormat('EEEE, MMMM d').format(now);
    final appBarDate = DateFormat('EEE, MMM d').format(now);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.today),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.md),
            child: Center(
              child: Text(
                appBarDate,
                style: AppTypography.labelLarge(color: AppColors.inkSecondary),
              ),
            ),
          ),
        ],
      ),
      body: babyId == null
          ? const _NoBabyPlaceholder()
          : _SummaryBody(babyId: babyId, dateLabel: dateLabel),
    );
  }
}

class _NoBabyPlaceholder extends StatelessWidget {
  const _NoBabyPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        context.l10n.summaryNoBabyProfile,
        style: AppTypography.bodyLarge(color: AppColors.inkSecondary),
      ),
    );
  }
}

class _SummaryBody extends ConsumerWidget {
  const _SummaryBody({required this.babyId, required this.dateLabel});

  final String babyId;
  final String dateLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final summaryAsync = ref.watch(dailySummaryProvider(babyId));
    final feedListAsync = ref.watch(feedTodayProvider(babyId));

    return summaryAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text(
          l10n.summaryLoadError,
          style: AppTypography.bodyLarge(color: AppColors.inkSecondary),
        ),
      ),
      data: (summary) {
        final feeds = feedListAsync.value ?? const <Feed>[];
        return SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                dateLabel,
                style: AppTypography.bodyLarge(color: AppColors.inkSecondary),
              ),
              const SizedBox(height: AppSpacing.md),

              // Feeding
              _SummaryCard(
                icon: Icons.water_drop_outlined,
                label: l10n.summaryFeedingLabel,
                value: summary.feedFormatted,
                color: AppColors.lavender700,
              ),
              const SizedBox(height: AppSpacing.xs),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: FeedSparkline(feeds: feeds),
              ),
              const SizedBox(height: AppSpacing.md),

              // Pump
              _SummaryCard(
                icon: Icons.compress_outlined,
                label: l10n.summaryPumpLabel,
                value: '${summary.pumpCount} sessions',
                color: AppColors.peach700,
              ),
              const SizedBox(height: AppSpacing.md),

              // Diaper
              _SummaryCard(
                icon: Icons.baby_changing_station_outlined,
                label: l10n.summaryDiapersLabel,
                value: '${summary.diaperCount} changes',
                color: AppColors.honey700,
              ),
              const SizedBox(height: AppSpacing.md),

              // Sleep
              _SummaryCard(
                icon: Icons.bedtime_outlined,
                label: l10n.homeQuickLogSleep,
                value: summary.sleepFormatted +
                    (summary.babyIsAsleep ? ' · ${l10n.summarySleepingNow}' : ''),
                color: AppColors.sage700,
              ),
              const SizedBox(height: AppSpacing.md),

              // Stash
              _SummaryCard(
                icon: Icons.ac_unit,
                label: l10n.stashTitle,
                value: summary.stashFormatted,
                color: AppColors.inkSecondary,
              ),
              const SizedBox(height: AppSpacing.lg),

              // Visit PDF (premium)
              _VisitPdfButton(babyId: babyId),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        );
      },
    );
  }
}

/// Generate Visit PDF action. Premium-gated — non-premium users see the
/// locked variant which routes to the paywall on tap. The unlocked variant
/// is a placeholder until Plan E wires the actual PDF generator.
class _VisitPdfButton extends StatelessWidget {
  const _VisitPdfButton({required this.babyId});

  final String babyId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PremiumGate(
      lockedChild: FilledButton.icon(
        icon: const Icon(Icons.lock_outline),
        label: Text(l10n.summaryGeneratePdf),
        onPressed: () => context.push(AppRoutes.premium),
        style: FilledButton.styleFrom(backgroundColor: Colors.grey),
      ),
      child: FilledButton.icon(
        icon: const Icon(Icons.picture_as_pdf_outlined),
        label: Text(l10n.summaryGeneratePdf),
        onPressed: () => context.push(AppRoutes.visitReport),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style:
                      AppTypography.labelLarge(color: AppColors.inkSecondary),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  value,
                  style: AppTypography.titleLarge(color: AppColors.inkPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
