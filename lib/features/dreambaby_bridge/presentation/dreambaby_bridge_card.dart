import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/features/dreambaby_bridge/data/dreambaby_bridge_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A card that surfaces the DreamBaby companion app.
///
/// - If DreamBaby is installed: shows "Open DreamBaby" (filled button).
/// - If DreamBaby is not installed: shows "Get DreamBaby" (outlined button)
///   that opens the Play Store listing.
/// - While loading or on error: returns [SizedBox.shrink] (silent optional UI).
///
/// This widget is intentionally not wired into any screen yet; it will be
/// placed in the Home or Settings screen during Plan F.
class DreamBabyBridgeCard extends ConsumerWidget {
  const DreamBabyBridgeCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installedAsync = ref.watch(dreamBabyInstalledProvider);

    return installedAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (installed) => Card(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              const Icon(
                Icons.music_note_outlined,
                color: AppColors.lavender700,
                size: 28,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'DreamBaby',
                  style: AppTypography.titleLarge(
                    color: AppColors.inkPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (installed)
                FilledButton(
                  onPressed: () =>
                      ref.read(dreamBabyBridgeServiceProvider).launch(),
                  child: Text(context.l10n.bridgeOpenApp),
                )
              else
                OutlinedButton(
                  onPressed: () =>
                      ref.read(dreamBabyBridgeServiceProvider).launch(),
                  child: Text(context.l10n.bridgeGetApp),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
