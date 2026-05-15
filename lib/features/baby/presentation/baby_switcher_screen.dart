import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/models/models.dart';
import '../../../core/providers/premium_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../data/baby_repository.dart';
import '../data/current_baby_provider.dart';
import 'add_baby_screen.dart';

/// Lists all active babies and lets the user switch between them.
///
/// Free tier is capped at 1 baby — tapping the + FAB when at the cap routes
/// to the paywall via [AppRoutes.premium]. Premium users can add unlimited.
///
/// AddBabyScreen is pushed as a modal `MaterialPageRoute` (per Plan D spec —
/// router stays untouched).
class BabySwitcherScreen extends ConsumerStatefulWidget {
  const BabySwitcherScreen({super.key});

  @override
  ConsumerState<BabySwitcherScreen> createState() =>
      _BabySwitcherScreenState();
}

class _BabySwitcherScreenState extends ConsumerState<BabySwitcherScreen> {
  late Future<List<Baby>> _babiesFuture;

  @override
  void initState() {
    super.initState();
    _babiesFuture = ref.read(babyRepositoryProvider).list();
  }

  void _reload() {
    setState(() {
      _babiesFuture = ref.read(babyRepositoryProvider).list();
    });
  }

  Future<void> _onAddTapped(int babyCount) async {
    final isPremium = ref.read(isPremiumProvider).value ?? false;
    if (!isPremium && babyCount >= 1) {
      // Free tier — already has 1 baby. Route to paywall.
      await context.push<void>(AppRoutes.premium);
      return;
    }
    final result = await Navigator.of(context).push<Baby>(
      MaterialPageRoute(builder: (_) => const AddBabyScreen()),
    );
    if (result != null && mounted) {
      _reload();
    }
  }

  Future<void> _onTileTapped(String babyId) async {
    await ref.read(currentBabyIdProvider.notifier).select(babyId);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final currentId = ref.watch(currentBabyIdProvider);
    final isPremiumAsync = ref.watch(isPremiumProvider);
    final isPremium = isPremiumAsync.value ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.babiesTitle),
      ),
      body: FutureBuilder<List<Baby>>(
        future: _babiesFuture,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text(l10n.errorGeneric));
          }
          final babies = snap.data ?? const <Baby>[];
          if (babies.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  l10n.babiesEmptyState,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium(
                    color: AppColors.inkSecondary,
                  ),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemCount: babies.length + (isPremium ? 0 : 1),
            separatorBuilder: (_, __) =>
                const Divider(height: 0, indent: AppSpacing.md),
            itemBuilder: (context, i) {
              if (i < babies.length) {
                final b = babies[i];
                return _BabyTile(
                  baby: b,
                  isSelected: b.id == currentId,
                  onTap: () => _onTileTapped(b.id),
                );
              }
              // Free-tier gate hint after the list (only when not premium).
              return InkWell(
                onTap: () => context.push(AppRoutes.premium),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.lock_outline,
                        size: 16,
                        color: AppColors.inkSecondary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          l10n.babiesFreeTierGate,
                          style: AppTypography.labelLarge(
                            color: AppColors.inkSecondary,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: AppColors.inkSecondary,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FutureBuilder<List<Baby>>(
        future: _babiesFuture,
        builder: (context, snap) {
          final count = snap.data?.length ?? 0;
          return FloatingActionButton.extended(
            onPressed: () => _onAddTapped(count),
            icon: const Icon(Icons.add),
            label: Text(l10n.babiesAddBaby),
          );
        },
      ),
    );
  }
}

class _BabyTile extends StatelessWidget {
  const _BabyTile({
    required this.baby,
    required this.isSelected,
    required this.onTap,
  });

  final Baby baby;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final dateFmt = DateFormat.yMMMd(Localizations.localeOf(context).toString());
    final bornOn = l10n.babiesDobBornOn(dateFmt.format(baby.dob));

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: AppColors.neutralMuted,
        child: Text(
          baby.name.isEmpty ? '?' : baby.name.characters.first.toUpperCase(),
          style: AppTypography.titleLarge(color: AppColors.inkPrimary),
        ),
      ),
      title: Text(
        baby.nickname?.isNotEmpty == true ? baby.nickname! : baby.name,
        style: AppTypography.titleLarge(color: scheme.onSurface),
      ),
      subtitle: Text(
        bornOn,
        style: AppTypography.bodyMedium(color: AppColors.inkSecondary),
      ),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: scheme.primary)
          : const Icon(Icons.chevron_right, color: AppColors.inkSecondary),
      onTap: onTap,
    );
  }
}
