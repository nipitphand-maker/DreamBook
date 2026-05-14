import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/features/stash/data/stash_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

export 'stash_repository.dart'
    show
        stashRepositoryProvider,
        stashAvailableProvider,
        StashAvailableNotifier;

/// Total oz available for [babyId], derived in Dart from [stashAvailableProvider].
final stashTotalOzProvider = Provider.family<AsyncValue<double>, String>(
  (ref, babyId) => ref.watch(stashAvailableProvider(babyId)).whenData(
        (bottles) => bottles.fold<double>(0, (sum, b) => sum + b.oz),
      ),
);

/// Bottles expiring within 2 days for [babyId].
final stashExpiringProvider =
    Provider.family<AsyncValue<List<StashBottle>>, String>(
  (ref, babyId) => ref.watch(stashAvailableProvider(babyId)).whenData(
        (bottles) {
          final cutoff = DateTime.now().add(const Duration(days: 2));
          return bottles.where((b) => b.expiresAt.isBefore(cutoff)).toList();
        },
      ),
);

/// Oldest available bottle for [babyId] (index 0 since FIFO), or null if empty.
final stashOldestProvider =
    Provider.family<AsyncValue<StashBottle?>, String>(
  (ref, babyId) => ref.watch(stashAvailableProvider(babyId)).whenData(
        (bottles) => bottles.isEmpty ? null : bottles.first,
      ),
);

/// Count of active (non-consumed, non-discarded, non-deleted) stash bottles
/// for [babyId]. Plan D Gating team uses this to enforce the free-tier cap
/// (20 bottles) and route to the paywall.
///
/// Returns `0` while loading or on error — fail-safe for gating logic so a
/// transient DB read does not accidentally unlock the cap.
final activeStashCountProvider = Provider.family<int, String>(
  (ref, babyId) =>
      ref.watch(stashAvailableProvider(babyId)).value?.length ?? 0,
);
