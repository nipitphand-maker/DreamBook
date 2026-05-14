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
