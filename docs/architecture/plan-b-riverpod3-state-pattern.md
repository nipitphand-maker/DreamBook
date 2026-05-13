# Plan B Senior Brief 2 — Riverpod 3 State Pattern

**Author:** Senior Flutter / Riverpod 3 engineer
**Date:** 2026-05-13

---

## TL;DR — Required Plan B provider conventions

- One `Provider<XRepository>` per table (NOT `AsyncNotifier<XRepository>`). Repos are stateless verb-bags; DB owns state.
- One `AsyncNotifierProvider.family<XTodayNotifier, List<X>, String>` per table keyed by `babyId`.
- Every write method on every repo **invalidates the matching `XTodayProvider(babyId)` after the transaction commits.**
- Every write transaction touches `sync_state` in the SAME `db.transaction((txn) async {...})` (atomic).
- All timestamps Dart-side `DateTime.now().toUtc().toIso8601String()`; all UUIDs Dart-side `Uuid().v4()`; all aggregated stats derived in Dart from already-watched today list (one read path).

## Provider DAG

```
sharedPreferencesProvider          (Provider, override in main)
appDatabaseProvider                (FutureProvider — Plan A) ─┐
                                                               ├─→ feedRepositoryProvider (Provider) ──┐
currentBabyIdProvider              (Notifier — Plan B new) ───┘                                          ├→ feedTodayProvider(babyId)
                                                                                                          │     (AsyncNotifier.family)
                                                                                                          ├→ feedOzTodayProvider(babyId)
                                                                                                          │     (Provider, derived in Dart)
                                                                                              (similarly: pump/diaper/sleep/stash)
```

## Live "Today" — invalidate-after-write (NOT polling)

Reject:
- StreamProvider over sqflite polling (battery drain)
- Riverpod AutoDispose.keepAlive + polled Stream (same)
- sqflite change callbacks (don't exist in sqflite_common)

**Use:** Manual `ref.invalidate(feedTodayProvider(babyId))` from inside repo write methods, AFTER transaction commits. Plan B is single-device; we own every state transition.

Plan C (sync) extends the same mechanism — sync worker calls `ref.invalidate` after each batch apply.

## Repository pattern — `FeedRepository.insert()` reference

```dart
Future<Feed> insert({
  required String babyId, required FeedType type, ...
}) async {
  final db = await _db;
  final now = DateTime.now().toUtc();
  final feed = Feed(id: _uuid.v4(), babyId: babyId, ..., 
                    createdAt: now, updatedAt: now, version: 1);

  await db.transaction((txn) async {
    await txn.insert('feed', feed.toRow());
    await txn.insert('sync_state', {
      'record_id': feed.id, 'table_name': 'feed',
      'version': 1, 'updated_at': now.toIso8601String(), 'dirty': 1,
    });
  });

  _ref.invalidate(feedTodayProvider(babyId));
  return feed;
}
```

`update()` uses optimistic concurrency `WHERE id = ? AND version = ?` — throws `ConcurrentUpdateException` on mismatch. `softDelete()` sets `deleted_at`, bumps version. All three touch `sync_state` in same transaction with `ConflictAlgorithm.replace`.

## Domain model — hand-rolled (freezed re-checked, STILL blocked)

Pub.dev 2026-05-13:
- `riverpod_generator 4.0.3` → analyzer `^9.0.0`
- `freezed 3.2.5` → analyzer `>=9.0.0 <11.0.0`
- `json_serializable 6.13.2` → analyzer `>=10.0.0 <14.0.0`

freezed + riverpod_generator overlap on analyzer 9. But json_serializable jumped to analyzer 10 → full trio still incompatible.

**Decision: hand-rolled `@immutable` classes with explicit `copyWith` + `toRow` + `fromRow`. Defer freezed to Plan C (needs json_serializable for AES-GCM blob serialization).**

## Aggregated stats — derived in Dart, NOT SQL

`feedOzTodayProvider` watches `feedTodayProvider` and folds in Dart:
```dart
final feedOzTodayProvider = Provider.family<AsyncValue<double>, String>(
  (ref, babyId) => ref.watch(feedTodayProvider(babyId)).whenData(
    (feeds) => feeds.fold<double>(0, (sum, f) => sum + (f.oz ?? 0)),
  ),
);
```

Why: one read path → free consistency between list and totals. Today's 8-15 entries don't warrant SQL aggregation. Plan E (Visit PDF over weeks) gets SQL aggregation as needed.

## Test strategy

Per repo: 6-10 unit tests via `sqflite_common_ffi` in-memory. Pattern already established in `/test/core/db/migrations_test.dart`.

Required test names for `feed_repository_test.dart`:
1. insert() persists feed row with required fields
2. insert() generates v4 UUID when none provided
3. insert() sets created_at = updated_at = now-utc
4. insert() writes sync_state row dirty=1 version=1
5. todayFor(babyId) returns only rows >= today-midnight-UTC
6. todayFor(babyId) excludes soft-deleted rows
7. update() bumps version by 1 and updates updated_at
8. update() throws ConcurrentUpdateException on version mismatch
9. softDelete() sets deleted_at, bumps version, marks sync_state dirty
10. insert/update/softDelete atomic — sync_state never out-of-sync after thrown error

Widget test: 1 smoke per screen, override `appDatabaseProvider` with in-memory db inside `ProviderContainer`.

Integration test: defer to Plan C/F (cipher only matters at real-device).

## 6 anti-patterns to forbid

1. `import 'package:flutter_riverpod/legacy.dart';` — banned per CLAUDE.md
2. `AsyncValue.valueOrNull` — removed in Riverpod 3; use `.value`
3. `ref.watch(provider.notifier).field` — silently misses rebuilds; use `ref.watch(provider).field` for state
4. `ref.read` inside `build()` of Notifier/AsyncNotifier — use `ref.watch` so notifier rebuilds when deps change
5. Using `ref` after `await` in mutator without recheck (Riverpod issue #4096)
6. Wrapping polling Stream in StreamProvider "for reactivity" — use `ref.invalidate` from write call sites instead
