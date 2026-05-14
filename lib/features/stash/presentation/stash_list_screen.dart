import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/premium_provider.dart';
import 'package:dreambook/core/router/app_router.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/stash/data/stash_providers.dart';
import 'package:dreambook/features/stash/data/stash_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
      appBar: AppBar(
        title: const Text('Freezer Stash'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add bottle',
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
    return const Center(child: Text('No baby selected'));
  }
}

class _StashBody extends ConsumerWidget {
  const _StashBody({required this.babyId});
  final String babyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottlesAsync = ref.watch(stashAvailableProvider(babyId));

    return bottlesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('Error: $err')),
      data: (bottles) {
        if (bottles.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'No milk in stash',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: AppSpacing.xs),
                Text(
                  'Bottles from pump sessions appear here',
                  style: TextStyle(color: AppColors.inkSecondary),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: bottles.length,
          itemBuilder: (context, index) => _BottleTile(
            bottle: bottles[index],
            babyId: babyId,
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Bottle tile
// ---------------------------------------------------------------------------

class _BottleTile extends ConsumerWidget {
  const _BottleTile({required this.bottle, required this.babyId});
  final StashBottle bottle;
  final String babyId;

  IconData _storageIcon(StorageType s) => switch (s) {
        StorageType.freezer => Icons.ac_unit,
        StorageType.fridge => Icons.kitchen,
        StorageType.room => Icons.thermostat,
      };

  Widget? _trailingBadge() {
    final now = DateTime.now();
    if (bottle.expiresAt.isBefore(now)) {
      return const Icon(Icons.error_outline, color: AppColors.lightError);
    }
    final cutoff = now.add(const Duration(days: 2));
    if (bottle.expiresAt.isBefore(cutoff)) {
      return const Icon(
        Icons.warning_amber_rounded,
        color: AppColors.honey700,
      );
    }
    return null;
  }

  String _relativeDate(DateTime dt) {
    final today = DateTime.now();
    final diff = DateTime(today.year, today.month, today.day)
        .difference(DateTime(dt.year, dt.month, dt.day))
        .inDays;
    if (diff == 0) return 'today';
    if (diff == 1) return 'yesterday';
    return '${diff}d ago';
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
    return ListTile(
      leading: Icon(_storageIcon(bottle.storage)),
      title: Text('${bottle.oz.toStringAsFixed(1)} oz'),
      subtitle: Text(
        'Pumped ${_relativeDate(bottle.pumpedAt)} · Expires ${_fmtDate(bottle.expiresAt)}',
      ),
      trailing: _trailingBadge(),
      onTap: () => _showBottleDetail(context, ref),
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

  String _storageName(StorageType s) => switch (s) {
        StorageType.freezer => 'Freezer',
        StorageType.fridge => 'Fridge',
        StorageType.room => 'Room temp',
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
              'Bottle details',
              style: AppTypography.titleLarge(color: AppColors.inkPrimary),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              '${bottle.oz.toStringAsFixed(1)} oz',
              style: AppTypography.headlineMedium(color: AppColors.inkPrimary),
            ),
            const SizedBox(height: AppSpacing.xs),
            Chip(label: Text(_storageName(bottle.storage))),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Pumped: ${_fmtDate(bottle.pumpedAt)}',
              style: AppTypography.bodyMedium(color: AppColors.inkSecondary),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Expires: ${_fmtDate(bottle.expiresAt)}',
              style: AppTypography.bodyMedium(color: AppColors.inkSecondary),
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
              child: const Text('Use this bottle'),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.lightError,
                side: const BorderSide(color: AppColors.lightError),
              ),
              onPressed: () => _confirmDiscard(context, ref),
              child: const Text('Discard'),
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
        title: const Text('Discard bottle?'),
        content: Text(
          'Are you sure you want to discard this ${bottle.oz.toStringAsFixed(1)} oz bottle?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.lightError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
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
              'Mark as used',
              style: AppTypography.titleLarge(color: AppColors.inkPrimary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Record that you used this bottle of '
              '${bottle.oz.toStringAsFixed(1)} oz',
              style: AppTypography.bodyMedium(color: AppColors.inkSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () => _confirm(context, ref),
              child: const Text('Confirm'),
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
        const SnackBar(content: Text('Bottle marked as used')),
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

  String _storageName(StorageType s) => switch (s) {
        StorageType.freezer => 'Freezer',
        StorageType.fridge => 'Fridge',
        StorageType.room => 'Room',
      };

  @override
  Widget build(BuildContext context) {
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
              'Add bottle',
              style: AppTypography.titleLarge(color: AppColors.inkPrimary),
            ),
            const SizedBox(height: AppSpacing.md),
            // Oz stepper
            Row(
              children: [
                Text(
                  'Amount (oz):',
                  style: AppTypography.bodyMedium(color: AppColors.inkSecondary),
                ),
                const Spacer(),
                IconButton.filled(
                  onPressed: _oz <= 0.5
                      ? null
                      : () => setState(() => _oz = double.parse(
                            (_oz - 0.5).toStringAsFixed(1),
                          )),
                  icon: const Icon(Icons.remove),
                ),
                const SizedBox(width: AppSpacing.xs),
                SizedBox(
                  width: 48,
                  child: Text(
                    _oz.toStringAsFixed(1),
                    textAlign: TextAlign.center,
                    style: AppTypography.numeric(
                      size: 18,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton.filled(
                  onPressed: () => setState(() => _oz = double.parse(
                        (_oz + 0.5).toStringAsFixed(1),
                      )),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Date picker
            Row(
              children: [
                Text(
                  'Pumped on:',
                  style: AppTypography.bodyMedium(color: AppColors.inkSecondary),
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
                      label: Text(_storageName(s)),
                    ),
                  )
                  .toList(),
              selected: {_storage},
              onSelectionChanged: (v) => setState(() => _storage = v.first),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
