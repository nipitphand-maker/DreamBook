import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/premium_provider.dart';
import 'package:dreambook/core/providers/unit_preferences_provider.dart';
import 'package:dreambook/core/router/app_router.dart';
import 'package:dreambook/core/services/unit_preferences.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/core/widgets/history_actions_menu.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/stash/data/stash_providers.dart';
import 'package:dreambook/features/stash/data/stash_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const _mlPerOz = 29.5735;

String _fmtVol(double oz, VolumeUnit unit) => unit == VolumeUnit.oz
    ? '${oz.toStringAsFixed(1)} oz'
    : '${(oz * _mlPerOz).round()} ml';

/// Free-tier maximum number of active stash bottles.
const int kStashFreeTierCap = 20;

/// Displays all available stash bottles for the current baby, FIFO ordered.
///
/// Route: `/stash`
class StashListScreen extends ConsumerWidget {
  const StashListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final babyId = ref.watch(currentBabyIdProvider);

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(context.l10n.stashTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: context.l10n.stashAddBottle,
            onPressed: babyId == null
                ? null
                : () => _handleAddBottle(context, ref, babyId),
          ),
        ],
      ),
      body: babyId == null
          ? const _NoBabyPlaceholder()
          : _StashBody(babyId: babyId),
    );
  }

  /// Counts active bottles, gates on free-tier cap, then either opens the
  /// add-bottle sheet or routes to the paywall.
  void _handleAddBottle(
    BuildContext context,
    WidgetRef ref,
    String babyId,
  ) {
    final isPremium = ref.read(isPremiumProvider).value ?? false;
    final activeCount =
        ref.read(stashAvailableProvider(babyId)).value?.length ?? 0;

    if (!isPremium && activeCount >= kStashFreeTierCap) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.stashCapReachedMessage)),
      );
      context.push(AppRoutes.premium);
      return;
    }

    _showAddBottleSheet(context, ref, babyId);
  }

  void _showAddBottleSheet(
    BuildContext context,
    WidgetRef ref,
    String babyId,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddBottleSheet(babyId: babyId),
    );
  }
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

class _NoBabyPlaceholder extends StatelessWidget {
  const _NoBabyPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(context.l10n.errorNoBabyProfile));
  }
}

// List item types for grouped display
sealed class _ListItem {}

class _HeaderItem extends _ListItem {
  _HeaderItem(this.type);
  final StorageType type;
}

class _BottleItem extends _ListItem {
  _BottleItem(this.bottle);
  final StashBottle bottle;
}

class _StashBody extends ConsumerStatefulWidget {
  const _StashBody({required this.babyId});
  final String babyId;

  @override
  ConsumerState<_StashBody> createState() => _StashBodyState();
}

class _StashBodyState extends ConsumerState<_StashBody> {
  String _searchQuery = '';

  List<_ListItem> _buildItems(List<StashBottle> bottles, VolumeUnit unit) {
    final q = _searchQuery.trim().toLowerCase();

    List<StashBottle> filtered = bottles;
    if (q.isNotEmpty) {
      filtered = bottles.where((b) {
        final volStr = unit == VolumeUnit.oz
            ? '${b.oz.toStringAsFixed(1)} oz'
            : '${(b.oz * _mlPerOz).round()} ml';
        final storageStr = switch (b.storage) {
          StorageType.freezer => 'freezer',
          StorageType.fridge => 'fridge',
          StorageType.room => 'room',
        };
        return volStr.toLowerCase().contains(q) || storageStr.contains(q);
      }).toList();
    }

    final items = <_ListItem>[];
    for (final type in StorageType.values) {
      final group = filtered
          .where((b) => b.storage == type)
          .toList()
        ..sort((a, b) => a.expiresAt.compareTo(b.expiresAt));
      if (group.isEmpty) continue;
      items.add(_HeaderItem(type));
      items.addAll(group.map(_BottleItem.new));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final bottlesAsync = ref.watch(stashAvailableProvider(widget.babyId));
    final unit = ref.watch(unitPreferencesProvider).volume;

    return bottlesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) =>
          Center(child: Text(context.l10n.stashError(err.toString()))),
      data: (bottles) {
        if (bottles.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.stashEmptyTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  context.l10n.stashEmptySubtitle,
                  style: const TextStyle(color: AppColors.inkSecondary),
                ),
              ],
            ),
          );
        }

        final items = _buildItems(bottles, unit);
        final showSearch = bottles.length > 10;
        final hasSearchQuery = _searchQuery.trim().isNotEmpty;
        final noResults = hasSearchQuery && items.whereType<_BottleItem>().isEmpty;

        return Column(
          children: [
            if (showSearch)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md, AppSpacing.sm, AppSpacing.md, 0),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: context.l10n.stashSearchHint,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
            if (noResults)
              Expanded(
                child: Center(
                  child: Text(
                    context.l10n.stashSearchEmpty(_searchQuery.trim()),
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium(
                        color: AppColors.inkSecondary),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: items.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _StashSummaryCard(bottles: bottles);
                    }
                    final item = items[index - 1];
                    return switch (item) {
                      _HeaderItem(:final type) => _StorageSectionHeader(type),
                      _BottleItem(:final bottle) => _BottleTile(
                          bottle: bottle,
                          babyId: widget.babyId,
                        ),
                    };
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

class _StorageSectionHeader extends StatelessWidget {
  const _StorageSectionHeader(this.type);
  final StorageType type;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (label, icon) = switch (type) {
      StorageType.freezer => (l10n.stashStorageFreezer, Icons.ac_unit),
      StorageType.fridge => (l10n.stashStorageFridge, Icons.kitchen),
      StorageType.room => (l10n.stashStorageRoom, Icons.thermostat),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.xxs),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.inkSecondary),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            style: AppTypography.labelLarge(color: AppColors.inkSecondary),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary card
// ---------------------------------------------------------------------------

class _StashSummaryCard extends ConsumerWidget {
  const _StashSummaryCard({required this.bottles});
  final List<StashBottle> bottles;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (bottles.isEmpty) return const SizedBox.shrink();

    final unit = ref.watch(unitPreferencesProvider).volume;
    final totalOz = bottles.fold<double>(0, (sum, b) => sum + b.oz);
    final ozDisplay = _fmtVol(totalOz, unit);
    final count = bottles.length;

    return Card(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            const Text('🧊', style: TextStyle(fontSize: 20)),
            const SizedBox(width: AppSpacing.xs),
            Text(
              context.l10n.stashSummaryTotal(ozDisplay, count),
              style: AppTypography.bodyMedium(
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottle tile
// ---------------------------------------------------------------------------

/// Freshness derived from what percentage of shelf life remains.
/// Pure function of (expiresAt, pumpedAt, now) — drives both the trailing
/// icon and the row-level border-left tint. Exposed at library scope so
/// widget tests can assert against it without touching internal `_BottleTile`.
enum _FreshnessState { expired, critical, warning, fresh }

_FreshnessState _freshnessFor(
  DateTime expiresAt,
  DateTime pumpedAt, {
  DateTime? now,
}) {
  final n = now ?? DateTime.now();
  if (!expiresAt.isAfter(n)) return _FreshnessState.expired;
  final total = expiresAt.difference(pumpedAt);
  if (total.inSeconds <= 0) return _FreshnessState.fresh;
  final remaining = expiresAt.difference(n);
  final pct = remaining.inSeconds / total.inSeconds;
  if (pct < 0.10) return _FreshnessState.critical;
  if (pct < 0.25) return _FreshnessState.warning;
  return _FreshnessState.fresh;
}

/// Border-left accent color per freshness state. Returns `null` for the
/// fresh case so the row stays visually quiet — only "needs attention"
/// rows draw a colored edge.
Color? _freshnessAccent(_FreshnessState state, Color errorColor) =>
    switch (state) {
      _FreshnessState.expired => errorColor,
      _FreshnessState.critical => errorColor,
      _FreshnessState.warning => AppColors.honey700,
      _FreshnessState.fresh => null,
    };

class _BottleTile extends ConsumerWidget {
  const _BottleTile({required this.bottle, required this.babyId});
  final StashBottle bottle;
  final String babyId;

  IconData _storageIcon(StorageType s) => switch (s) {
        StorageType.freezer => Icons.ac_unit,
        StorageType.fridge => Icons.kitchen,
        StorageType.room => Icons.thermostat,
      };

  Widget? _trailingBadge(_FreshnessState state, Color errorColor) =>
      switch (state) {
        _FreshnessState.expired || _FreshnessState.critical => Icon(
            Icons.error_outline,
            color: errorColor,
          ),
        _FreshnessState.warning => const Icon(
            Icons.warning_amber_rounded,
            color: AppColors.honey700,
          ),
        _FreshnessState.fresh => null,
      };

  String _relativeDate(BuildContext context, DateTime dt) {
    final today = DateTime.now();
    final diff = DateTime(today.year, today.month, today.day)
        .difference(DateTime(dt.year, dt.month, dt.day))
        .inDays;
    if (diff == 0) return context.l10n.stashRelativeToday;
    if (diff == 1) return context.l10n.stashRelativeYesterday;
    return context.l10n.stashRelativeDaysAgo(diff);
  }

  String _fmtDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final unit = ref.watch(unitPreferencesProvider).volume;
    final freshness = _freshnessFor(bottle.expiresAt, bottle.pumpedAt);
    final errorColor = Theme.of(context).colorScheme.error;
    final accent = _freshnessAccent(freshness, errorColor);
    final badge = _trailingBadge(freshness, errorColor);
    final actions = HistoryActionsMenu(
      key: Key('stash_history_${bottle.id}'),
      rowLoggedBy: bottle.loggedBy,
      onEdit: () => _showEditSheet(context),
      onDelete: () async {
        await ref
            .read(stashRepositoryProvider)
            .softDelete(bottle.id, babyId: babyId);
      },
      confirmTitle: l10n.historyActionConfirmDeleteStash,
      confirmBody: l10n.historyActionConfirmDeleteStashBody,
    );
    // 4px colored left edge marks rows that need attention (expired /
    // near-expiry). Fresh rows get a fully transparent border so every
    // row keeps the same horizontal alignment — no jitter as bottles
    // shift between states day-to-day.
    return Container(
      key: Key('stash_tile_${bottle.id}'),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: accent ?? Colors.transparent,
            width: 4,
          ),
        ),
      ),
      child: ListTile(
        leading: Icon(_storageIcon(bottle.storage)),
        title: Text(_fmtVol(bottle.oz, unit)),
        subtitle: Text(
          l10n.stashPumpedExpires(
            _relativeDate(context, bottle.pumpedAt),
            _fmtDate(bottle.expiresAt),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badge != null) badge,
            actions,
          ],
        ),
        onTap: () => _showBottleDetail(context, ref),
      ),
    );
  }

  void _showEditSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _StashEditSheet(bottle: bottle, babyId: babyId),
    );
  }

  void _showBottleDetail(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _BottleDetailSheet(bottle: bottle, babyId: babyId),
    );
  }
}

// ---------------------------------------------------------------------------
// B4.4 — Bottle detail sheet
// ---------------------------------------------------------------------------

class _BottleDetailSheet extends ConsumerWidget {
  const _BottleDetailSheet({required this.bottle, required this.babyId});
  final StashBottle bottle;
  final String babyId;

  String _storageName(BuildContext context, StorageType s) => switch (s) {
        StorageType.freezer => context.l10n.stashStorageFreezer,
        StorageType.fridge => context.l10n.stashStorageFridge,
        StorageType.room => context.l10n.stashStorageRoom,
      };

  String _fmtDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(unitPreferencesProvider).volume;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.stashBottleDetails,
              style: AppTypography.titleLarge(color: scheme.onSurface),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _fmtVol(bottle.oz, unit),
              style: AppTypography.headlineMedium(color: scheme.onSurface),
            ),
            const SizedBox(height: AppSpacing.xs),
            Chip(label: Text(_storageName(context, bottle.storage))),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.l10n.stashPumpedAtLabel(_fmtDate(bottle.pumpedAt)),
              style: AppTypography.bodyMedium(
                  color: scheme.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              context.l10n.stashExpiresAtLabel(_fmtDate(bottle.expiresAt)),
              style: AppTypography.bodyMedium(
                  color: scheme.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) =>
                      _ConsumeBottleSheet(bottle: bottle, babyId: babyId),
                );
              },
              child: Text(context.l10n.stashUseBottle),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
                side: BorderSide(color: Theme.of(context).colorScheme.error),
              ),
              onPressed: () => _confirmDiscard(context, ref),
              child: Text(context.l10n.stashDiscard),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDiscard(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.stashDiscardTitle),
        content: Text(
          context.l10n.stashDiscardConfirm(
            _fmtVol(bottle.oz, ref.read(unitPreferencesProvider).volume),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.l10n.actionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.l10n.stashDiscard),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await ref
          .read(stashRepositoryProvider)
          .discard(bottle.id, babyId: babyId);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}

// ---------------------------------------------------------------------------
// B4.5 — Consume bottle sheet
// ---------------------------------------------------------------------------

class _ConsumeBottleSheet extends ConsumerWidget {
  const _ConsumeBottleSheet({required this.bottle, required this.babyId});
  final StashBottle bottle;
  final String babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unit = ref.watch(unitPreferencesProvider).volume;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.stashMarkAsUsed,
              style: AppTypography.titleLarge(color: scheme.onSurface),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.l10n.stashMarkUsedDescription(_fmtVol(bottle.oz, unit)),
              style: AppTypography.bodyMedium(
                  color: scheme.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () => _confirm(context, ref),
              child: Text(context.l10n.actionConfirm),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    await ref
        .read(stashRepositoryProvider)
        .consume(bottle.id, babyId: babyId);
    if (context.mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.stashBottleUsed)),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Add bottle sheet
// ---------------------------------------------------------------------------

class _AddBottleSheet extends ConsumerStatefulWidget {
  const _AddBottleSheet({required this.babyId});
  final String babyId;

  @override
  ConsumerState<_AddBottleSheet> createState() => _AddBottleSheetState();
}

class _AddBottleSheetState extends ConsumerState<_AddBottleSheet> {
  double _oz = 4.0;
  DateTime _pumpedAt = DateTime.now();
  StorageType _storage = StorageType.freezer;

  String _fmtDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _pumpedAt,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _pumpedAt = picked);
    }
  }

  Future<void> _save() async {
    await ref.read(stashRepositoryProvider).insertManual(
          babyId: widget.babyId,
          oz: _oz,
          pumpedAt: _pumpedAt,
          storage: _storage,
        );
    if (mounted) Navigator.of(context).pop();
  }

  String _storageName(BuildContext context, StorageType s) => switch (s) {
        StorageType.freezer => context.l10n.stashStorageFreezer,
        StorageType.fridge => context.l10n.stashStorageFridge,
        StorageType.room => context.l10n.stashStorageRoomShort,
      };

  @override
  Widget build(BuildContext context) {
    final unit = ref.watch(unitPreferencesProvider).volume;
    final isOz = unit == VolumeUnit.oz;
    final step = isOz ? 0.5 : 5 / _mlPerOz;
    final maxOz = isOz ? 16.0 : 500 / _mlPerOz;
    final scheme = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.md,
          top: AppSpacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.l10n.stashAddBottle,
              style: AppTypography.titleLarge(color: scheme.onSurface),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Text(
                  context.l10n.stashAmountLabel(isOz ? 'oz' : 'ml'),
                  style: AppTypography.bodyMedium(
                      color: scheme.onSurface.withValues(alpha: 0.6)),
                ),
                const Spacer(),
                IconButton.filled(
                  onPressed: _oz <= 0.5
                      ? null
                      : () => setState(
                          () => _oz = (_oz - step).clamp(0.5, maxOz)),
                  icon: const Icon(Icons.remove),
                ),
                const SizedBox(width: AppSpacing.xs),
                SizedBox(
                  width: 56,
                  child: Text(
                    isOz
                        ? _oz.toStringAsFixed(1)
                        : '${(_oz * _mlPerOz).round()}',
                    textAlign: TextAlign.center,
                    style: AppTypography.numeric(
                      size: 18,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton.filled(
                  onPressed: _oz >= maxOz
                      ? null
                      : () => setState(
                          () => _oz = (_oz + step).clamp(0.5, maxOz)),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Date picker
            Row(
              children: [
                Text(
                  context.l10n.stashPumpedOnLabel,
                  style: AppTypography.bodyMedium(
                      color: scheme.onSurface.withValues(alpha: 0.6)),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _pickDate,
                  child: Text(_fmtDate(_pumpedAt)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Storage toggle
            SegmentedButton<StorageType>(
              segments: StorageType.values
                  .map(
                    (s) => ButtonSegment(
                      value: s,
                      label: Text(_storageName(context, s)),
                    ),
                  )
                  .toList(),
              selected: {_storage},
              onSelectionChanged: (v) => setState(() => _storage = v.first),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _save,
              child: Text(context.l10n.actionSave),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stash edit sheet — invoked from HistoryActionsMenu › Edit
// ---------------------------------------------------------------------------

class _StashEditSheet extends ConsumerStatefulWidget {
  const _StashEditSheet({required this.bottle, required this.babyId});

  final StashBottle bottle;
  final String babyId;

  @override
  ConsumerState<_StashEditSheet> createState() => _StashEditSheetState();
}

class _StashEditSheetState extends ConsumerState<_StashEditSheet> {
  late double _oz;
  late DateTime _pumpedAt;
  late StorageType _storage;

  @override
  void initState() {
    super.initState();
    _oz = widget.bottle.oz;
    _pumpedAt = widget.bottle.pumpedAt.toLocal();
    _storage = widget.bottle.storage;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _pumpedAt,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _pumpedAt = picked);
  }

  String _fmtDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _storageName(BuildContext context, StorageType s) => switch (s) {
        StorageType.freezer => context.l10n.stashStorageFreezer,
        StorageType.fridge => context.l10n.stashStorageFridge,
        StorageType.room => context.l10n.stashStorageRoomShort,
      };

  Future<void> _save() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final next = widget.bottle.copyWith(
      oz: _oz,
      pumpedAt: _pumpedAt,
      storage: _storage,
    );
    try {
      await ref.read(stashRepositoryProvider).update(next);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(l10n.historyEditSaved)));
    } on StateError {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.historyEditConflict)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final unit = ref.watch(unitPreferencesProvider).volume;
    final isOz = unit == VolumeUnit.oz;
    final step = isOz ? 0.5 : 5 / _mlPerOz;
    final maxOz = isOz ? 16.0 : 500 / _mlPerOz;
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.md,
          top: AppSpacing.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.historyEditStashTitle,
              style: AppTypography.titleLarge(color: scheme.onSurface),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Text(
                  l10n.stashAmountLabel(isOz ? 'oz' : 'ml'),
                  style: AppTypography.bodyMedium(
                      color: scheme.onSurface.withValues(alpha: 0.6)),
                ),
                const Spacer(),
                IconButton.filled(
                  onPressed: _oz <= 0.5
                      ? null
                      : () => setState(
                          () => _oz = (_oz - step).clamp(0.5, maxOz)),
                  icon: const Icon(Icons.remove),
                ),
                const SizedBox(width: AppSpacing.xs),
                SizedBox(
                  width: 56,
                  child: Text(
                    isOz
                        ? _oz.toStringAsFixed(1)
                        : '${(_oz * _mlPerOz).round()}',
                    textAlign: TextAlign.center,
                    style: AppTypography.numeric(
                      size: 18,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton.filled(
                  onPressed: _oz >= maxOz
                      ? null
                      : () => setState(
                          () => _oz = (_oz + step).clamp(0.5, maxOz)),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Text(
                  l10n.stashPumpedOnLabel,
                  style: AppTypography.bodyMedium(
                      color: scheme.onSurface.withValues(alpha: 0.6)),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _pickDate,
                  child: Text(_fmtDate(_pumpedAt)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SegmentedButton<StorageType>(
              segments: StorageType.values
                  .map(
                    (s) => ButtonSegment(
                      value: s,
                      label: Text(_storageName(context, s)),
                    ),
                  )
                  .toList(),
              selected: {_storage},
              onSelectionChanged: (v) => setState(() => _storage = v.first),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: _save, child: Text(l10n.actionSave)),
          ],
        ),
      ),
    );
  }
}
