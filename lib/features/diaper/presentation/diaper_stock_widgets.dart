import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/features/diaper/data/diaper_stock_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tracks whether the user has dismissed the [DiaperStockHintCard].
///
/// Read from SharedPreferences under `diaper.stock.hint.dismissed`. Watched by
/// the hint card; invalidated when the user taps the close icon so the card
/// disappears immediately.
final diaperStockHintDismissedProvider =
    Provider.family<bool, String>((ref, babyId) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return prefs.getBool(_hintDismissedKey) ?? false;
});

const String _hintDismissedKey = 'diaper.stock.hint.dismissed';

// ── Restock dialog ──────────────────────────────────────────────────────────

/// Shows the "Restock diapers" dialog for [babyId].
///
/// If the user already has tracking enabled, the field is prefilled with the
/// current pack size and a "Stop tracking" button is shown.
Future<void> showDiaperRestockDialog(
  BuildContext context,
  WidgetRef ref,
  String babyId,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _DiaperRestockDialog(babyId: babyId),
  );
}

class _DiaperRestockDialog extends ConsumerStatefulWidget {
  const _DiaperRestockDialog({required this.babyId});
  final String babyId;

  @override
  ConsumerState<_DiaperRestockDialog> createState() =>
      _DiaperRestockDialogState();
}

class _DiaperRestockDialogState extends ConsumerState<_DiaperRestockDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    final stock = ref.read(diaperStockProvider(widget.babyId));
    _ctrl = TextEditingController(
      text: stock != null ? stock.initial.toString() : '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final raw = _ctrl.text.trim();
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.diaperStockErrorInvalid)),
      );
      return;
    }
    final prefs = ref.read(sharedPreferencesProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final savedMsg = l10n.diaperStockSavedSnack;

    await DiaperStockService.restock(prefs, widget.babyId, parsed);
    if (!mounted) return;
    ref.invalidate(diaperStockProvider(widget.babyId));
    navigator.pop();
    messenger.showSnackBar(SnackBar(content: Text(savedMsg)));
  }

  Future<void> _stopTracking() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final navigator = Navigator.of(context);
    await DiaperStockService.clear(prefs, widget.babyId);
    if (!mounted) return;
    ref.invalidate(diaperStockProvider(widget.babyId));
    // clear() also resets the hint-dismissed flag so the discovery hint
    // can reappear on Home — refresh the provider so the UI rebuilds.
    ref.invalidate(diaperStockHintDismissedProvider(widget.babyId));
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final stock = ref.watch(diaperStockProvider(widget.babyId));
    final hasTracking = stock != null;

    return AlertDialog(
      title: Text(l10n.diaperStockRestockTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: false,
              signed: false,
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: l10n.diaperStockPackSizeHint,
            ),
          ),
          if (hasTracking) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.diaperStockCurrentRemaining(stock.current, stock.initial),
              style: AppTypography.labelLarge(
                color: AppColors.inkSecondary,
              ),
            ),
          ],
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        if (hasTracking)
          TextButton.icon(
            onPressed: _stopTracking,
            icon: const Icon(Icons.delete_outline, size: 18),
            label: Text(l10n.diaperStockStopTracking),
          )
        else
          const SizedBox.shrink(),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.actionCancel),
            ),
            const SizedBox(width: AppSpacing.xxs),
            FilledButton(
              onPressed: _save,
              child: Text(l10n.actionSave),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Low-stock banner ────────────────────────────────────────────────────────

/// Banner shown above the diaper section when the pack is running low.
///
/// Hidden entirely when:
///   * Stock tracking is disabled (`stock == null`), OR
///   * The pack is comfortably above 25% remaining (`!shouldAlert`).
///
/// Tap anywhere on the banner to re-open the restock dialog.
class DiaperStockBanner extends ConsumerWidget {
  const DiaperStockBanner({super.key, required this.babyId});
  final String babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = ref.watch(diaperStockProvider(babyId));
    if (stock == null || !stock.shouldAlert) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isCritical = stock.isCritical;

    final Color bg;
    final Color fg;
    if (isCritical) {
      bg = scheme.errorContainer;
      fg = scheme.onErrorContainer;
    } else {
      bg = AppColors.honey700.withValues(alpha: 0.15);
      fg = AppColors.honey700;
    }

    final String message;
    if (stock.current == 0) {
      message = l10n.diaperStockBannerEmpty;
    } else if (isCritical) {
      message = l10n.diaperStockBannerCritical(stock.current);
    } else {
      message = l10n.diaperStockBannerWarning(stock.current, stock.initial);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.md),
          onTap: () => showDiaperRestockDialog(context, ref, babyId),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 18, color: fg),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      message,
                      style: AppTypography.labelLarge(color: fg),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 16, color: fg),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── First-run hint card ─────────────────────────────────────────────────────

/// Subtle card suggesting the user enable diaper stock tracking.
///
/// Hidden when the user is already tracking (`stock != null`) or has tapped
/// the close icon (`diaper.stock.hint.dismissed = true` in SharedPreferences).
class DiaperStockHintCard extends ConsumerWidget {
  const DiaperStockHintCard({super.key, required this.babyId});
  final String babyId;

  Future<void> _dismiss(WidgetRef ref) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_hintDismissedKey, true);
    ref.invalidate(diaperStockHintDismissedProvider(babyId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stock = ref.watch(diaperStockProvider(babyId));
    final dismissed = ref.watch(diaperStockHintDismissedProvider(babyId));
    if (stock != null || dismissed) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.md),
          onTap: () => showDiaperRestockDialog(context, ref, babyId),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppSpacing.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.md,
                right: AppSpacing.xxs,
                top: AppSpacing.xs,
                bottom: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lightbulb_outline,
                    size: 18,
                    color: AppColors.inkSecondary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      l10n.diaperStockHint,
                      style: AppTypography.labelLarge(
                        color: AppColors.inkSecondary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    color: AppColors.inkSecondary,
                    tooltip: l10n.actionCancel,
                    onPressed: () => _dismiss(ref),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
