import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/features/diaper/data/diaper_repository.dart';
import 'package:dreambook/features/feed/data/feed_repository.dart';
import 'package:dreambook/features/pump/data/pump_repository.dart';
import 'package:dreambook/features/sleep/data/sleep_repository.dart';
import 'package:dreambook/features/stash/data/stash_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A single row in the Home "Today" chronological activity feed.
///
/// Each subclass corresponds to one row source (feed / pump / diaper / sleep /
/// stash-bottle-added). The `id` is the source row's primary key so taps can
/// deep-link into the per-feature edit flow once it exists; `timestamp` is the
/// authoritative time the event happened (started_at / occurred_at / pumped_at).
@immutable
sealed class HomeTimelineEntry {
  const HomeTimelineEntry({required this.id, required this.timestamp});

  /// Source row primary key. Stable across rebuilds for ListView keys.
  final String id;

  /// Wall-clock instant the event happened. Compared for sort + display.
  final DateTime timestamp;
}

class FeedTimelineEntry extends HomeTimelineEntry {
  FeedTimelineEntry(this.feed)
      : super(id: 'feed:${feed.id}', timestamp: feed.startedAt);
  final Feed feed;
}

class PumpTimelineEntry extends HomeTimelineEntry {
  PumpTimelineEntry(this.session)
      : super(id: 'pump:${session.id}', timestamp: session.startedAt);
  final PumpSession session;
}

class DiaperTimelineEntry extends HomeTimelineEntry {
  DiaperTimelineEntry(this.diaper)
      : super(id: 'diaper:${diaper.id}', timestamp: diaper.occurredAt);
  final Diaper diaper;
}

class SleepTimelineEntry extends HomeTimelineEntry {
  SleepTimelineEntry(this.sleep)
      : super(id: 'sleep:${sleep.id}', timestamp: sleep.startedAt);
  final Sleep sleep;
}

class StashAddTimelineEntry extends HomeTimelineEntry {
  StashAddTimelineEntry(this.bottle)
      : super(id: 'stash:${bottle.id}', timestamp: bottle.pumpedAt);
  final StashBottle bottle;
}

/// Unified, reverse-chronological list of today's events for [babyId].
///
/// Watches the existing per-feature today providers — anything that already
/// invalidates them (writes from the local user OR `onAfterPull` after a
/// realtime/REST sync) will rebuild this list for free.
///
/// Returns the merged list sorted `timestamp DESC` (freshest first).
///
/// While ANY upstream is loading we surface `AsyncValue.loading()` so the UI
/// can render a single shimmer instead of a half-populated list that flickers
/// as each source resolves.
final homeTodayTimelineProvider =
    Provider.family<AsyncValue<List<HomeTimelineEntry>>, String>(
  (ref, babyId) {
    final feeds = ref.watch(feedTodayProvider(babyId));
    final pumps = ref.watch(pumpTodayProvider(babyId));
    final diapers = ref.watch(diaperTodayProvider(babyId));
    final sleeps = ref.watch(sleepTodayProvider(babyId));
    final bottles = ref.watch(stashAvailableProvider(babyId));

    // Bubble up errors from any source so the parent can show a retry banner.
    for (final src in [feeds, pumps, diapers, sleeps, bottles]) {
      final err = src.error;
      if (err != null) {
        return AsyncValue.error(err, src.stackTrace ?? StackTrace.current);
      }
    }
    // If any source is still loading, defer — empty-state checks must wait
    // for ground truth, otherwise we'd flicker through "no activity" on first
    // open and racing rebuilds would re-flicker on each provider resolve.
    if (feeds.isLoading ||
        pumps.isLoading ||
        diapers.isLoading ||
        sleeps.isLoading ||
        bottles.isLoading) {
      return const AsyncValue.loading();
    }

    final entries = <HomeTimelineEntry>[
      ...(feeds.value ?? const <Feed>[]).map(FeedTimelineEntry.new),
      ...(pumps.value ?? const <PumpSession>[]).map(PumpTimelineEntry.new),
      ...(diapers.value ?? const <Diaper>[]).map(DiaperTimelineEntry.new),
      ...(sleeps.value ?? const <Sleep>[]).map(SleepTimelineEntry.new),
      // Stash: only bottles added TODAY count as an event. The
      // `stashAvailableProvider` already excludes consumed/discarded/deleted,
      // so we just filter by `pumpedAt` falling within the local day.
      ...(bottles.value ?? const <StashBottle>[])
          .where((b) => _isToday(b.pumpedAt))
          .map(StashAddTimelineEntry.new),
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return AsyncValue.data(List.unmodifiable(entries));
  },
);

bool _isToday(DateTime when) {
  final now = DateTime.now();
  final t = when.toLocal();
  return t.year == now.year && t.month == now.month && t.day == now.day;
}
