import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/features/feed/data/feed_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Total oz fed today for [babyId], derived in Dart from [feedTodayProvider].
///
/// Per the senior brief: one read path, free consistency with the list.
/// Anything that watches the timeline already pays the query — folding over
/// it costs ~zero, and the two views can never drift.
final feedOzTodayProvider = Provider.family<AsyncValue<double>, String>(
  (ref, babyId) => ref.watch(feedTodayProvider(babyId)).whenData(
        (feeds) => feeds.fold<double>(0, (sum, f) => sum + (f.oz ?? 0)),
      ),
);

/// Last 3 feeds today for [babyId], for the Home "Today timeline" row.
///
/// `feedTodayProvider` is already ordered `started_at DESC`, so `take(3)`
/// yields the freshest three.
final feedRecentTodayProvider = Provider.family<AsyncValue<List<Feed>>, String>(
  (ref, babyId) => ref.watch(feedTodayProvider(babyId)).whenData(
        (feeds) => feeds.take(3).toList(growable: false),
      ),
);
