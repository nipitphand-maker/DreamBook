import 'dart:async';

import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/core/widgets/logged_at_chip.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/diaper/data/diaper_repository.dart';
import 'package:dreambook/features/diaper/data/diaper_stock_provider.dart';
import 'package:dreambook/features/diaper/presentation/diaper_history_section.dart';
import 'package:dreambook/features/diaper/presentation/diaper_stock_widgets.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dreambook/core/router/app_router.dart';
import 'package:go_router/go_router.dart';

/// Quick-log diaper — designed for one-handed 3 AM use.
/// Route: /diaper/new
class DiaperLogScreen extends ConsumerStatefulWidget {
  const DiaperLogScreen({super.key});

  @override
  ConsumerState<DiaperLogScreen> createState() => _DiaperLogScreenState();
}

class _DiaperLogScreenState extends ConsumerState<DiaperLogScreen> {
  DiaperType? _selectedType;

  // null = now; non-null = the specific past time the user picked
  DateTime? _loggedAt;

  final _notesCtrl = TextEditingController();

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickToday() async {
    final picked = await pickTodayTime(context);
    if (picked != null && mounted) setState(() => _loggedAt = picked);
  }

  Future<void> _pickPast() async {
    final picked = await pickPastDateTime(context, _loggedAt);
    if (picked != null && mounted) setState(() => _loggedAt = picked);
  }

  Future<void> _save() async {
    if (_selectedType == null) return;

    final babyId = ref.read(currentBabyIdProvider);
    if (babyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.errorNoBabyProfile)),
      );
      return;
    }

    final repo = ref.read(diaperRepositoryProvider);
    final note =
        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    await repo.insert(
      babyId: babyId,
      type: _selectedType!,
      occurredAt: _loggedAt,
      note: note,
    );

    unawaited(HapticFeedback.lightImpact());
    if (!mounted) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _selectedType != null;
    final babyId = ref.watch(currentBabyIdProvider);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: Text(context.l10n.diaperAppBarTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xs),
              // Compact stock pill (visible when tracking is enabled OR as
              // a one-time discovery nudge). Tappable → restock dialog.
              if (babyId != null) _DiaperStockPill(babyId: babyId),
              const SizedBox(height: AppSpacing.sm),
              // Type selector — 2×2 grid of tap targets. childAspectRatio 2.2
              // makes the tiles wider+shorter to free vertical space for the
              // stock pill above.
              GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: AppSpacing.sm,
                  crossAxisSpacing: AppSpacing.sm,
                  childAspectRatio: 2.2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _TypeButton(
                      icon: Icons.water_drop_outlined,
                      label: context.l10n.diaperPee,
                      color: AppColors.lightWarning.withValues(alpha: 0.22),
                      selected: _selectedType == DiaperType.pee,
                      onTap: () =>
                          setState(() => _selectedType = DiaperType.pee),
                    ),
                    _TypeButton(
                      icon: Icons.circle,
                      label: context.l10n.diaperPoop,
                      color: AppColors.lightAccent.withValues(alpha: 0.35),
                      selected: _selectedType == DiaperType.poop,
                      onTap: () =>
                          setState(() => _selectedType = DiaperType.poop),
                    ),
                    _TypeButton(
                      icon: Icons.water_drop,
                      label: context.l10n.diaperMixed,
                      color: AppColors.lightPrimary.withValues(alpha: 0.25),
                      selected: _selectedType == DiaperType.mixed,
                      onTap: () =>
                          setState(() => _selectedType = DiaperType.mixed),
                    ),
                    _TypeButton(
                      icon: Icons.do_not_disturb_alt_outlined,
                      label: context.l10n.diaperDry,
                      color: Colors.grey.shade100,
                      selected: _selectedType == DiaperType.dry,
                      onTap: () =>
                          setState(() => _selectedType = DiaperType.dry),
                    ),
                  ],
              ),
              const SizedBox(height: AppSpacing.md),
              // Time picker — tap to log as past
              LoggedAtChip(
                value: _loggedAt,
                onTapToday: _pickToday,
                onTapPast: _pickPast,
                onClear: _loggedAt != null
                    ? () => setState(() => _loggedAt = null)
                    : null,
              ),
              const SizedBox(height: AppSpacing.md),
              // Notes
              TextField(
                controller: _notesCtrl,
                maxLines: 2,
                maxLength: 240,
                decoration: InputDecoration(
                  labelText: context.l10n.diaperNotesOptional,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              // Save button
              FilledButton(
                onPressed: canSave ? _save : null,
                child: Text(context.l10n.actionSave),
              ),
              const SizedBox(height: AppSpacing.lg),
              // Today's history — fills remaining space, scrolls if needed.
              if (babyId != null)
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Divider(),
                        _DiaperTodaySummary(babyId: babyId),
                        DiaperHistorySection(babyId: babyId),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Today summary bar
// ---------------------------------------------------------------------------

class _DiaperTodaySummary extends ConsumerWidget {
  const _DiaperTodaySummary({required this.babyId});
  final String babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return ref.watch(diaperTodayProvider(babyId)).when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (diapers) {
        final String detail;
        if (diapers.isEmpty) {
          detail = l10n.todayNoDiapersYet;
        } else {
          detail = l10n.diaperCountToday(diapers.length);
        }

        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '${l10n.todaySummaryPrefix}$detail',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        );
      },
    );
  }
}

// Stock pill — compact "เหลือ X/Y" badge. Tappable → restock dialog.
// Color tracks the same critical/warning thresholds as the home banner.
class _DiaperStockPill extends ConsumerWidget {
  const _DiaperStockPill({required this.babyId});
  final String babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final stock = ref.watch(diaperStockProvider(babyId));

    // Pick colors + label per state.
    final Color bg;
    final Color fg;
    final IconData icon;
    final String label;
    if (stock == null) {
      bg = scheme.surfaceContainerHigh;
      fg = scheme.onSurface.withValues(alpha: 0.7);
      icon = Icons.inventory_2_outlined;
      label = l10n.diaperStockHint;
    } else if (stock.isCritical) {
      bg = scheme.errorContainer;
      fg = scheme.onErrorContainer;
      icon = Icons.inventory_2_outlined;
      label = stock.current == 0
          ? l10n.diaperStockBannerEmpty
          : l10n.diaperStockBannerCritical(stock.current);
    } else if (stock.isWarning) {
      bg = AppColors.honey700.withValues(alpha: 0.15);
      fg = AppColors.honey700;
      icon = Icons.inventory_2_outlined;
      label = l10n.diaperStockBannerWarning(stock.current, stock.initial);
    } else {
      // Plenty left — neutral info pill so user always knows the count.
      bg = scheme.surfaceContainerHigh;
      fg = scheme.onSurface.withValues(alpha: 0.8);
      icon = Icons.inventory_2_outlined;
      label = l10n.diaperStockCurrentRemaining(stock.current, stock.initial);
    }

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        onTap: () => showDiaperRestockDialog(context, ref, babyId),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
          child: Row(
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.labelLarge(color: fg),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypeButton extends StatelessWidget {
  const _TypeButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onTap,
        child: Container(
          decoration: selected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  border: Border.all(
                    color: AppColors.lavender700,
                    width: 3,
                  ),
                )
              : null,
          constraints:
              const BoxConstraints(minHeight: AppSpacing.minTouchTarget),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 26, color: AppColors.inkPrimary),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyLarge(color: AppColors.inkPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
