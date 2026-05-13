# Plan B Sketch — Local Logging

**Status:** Sketch for user approval. Full plan (with inline code per task) will be written after user OKs scope + task count.

**Goal:** Make the app actually useful — log feeds, pumps, diapers, sleep on-device; freezer stash with CDC-correct expiry transitions; daily summary with sparkline. All offline-only (sync comes Plan C).

**Sub-phases** (sequential within Plan B; each leaves the app build-green):
- **B.1 Migration v2 + Models + Baby/Caregiver foundation** (5 tasks)
- **B.2 Feed CRUD + screen + Home wiring** (4 tasks)
- **B.3 Pump CRUD + screen + bottle splitting + Settings portion config** (6 tasks)
- **B.4 Stash CRUD + screen + detail sheet + Consume flow + FIFO Home card** (6 tasks)
- **B.5 Diaper CRUD + screen** (2 tasks)
- **B.6 Sleep CRUD + screen + in-flight timer** (3 tasks)
- **B.7 Daily Summary screen + fl_chart sparkline + premium-gated PDF tile** (4 tasks)
- **B.8 Final gate** (1 task: analyze + test + smoke)

**Total: ~31 tasks.** At Plan A's pace (~6-10 min per task incl 2-stage review), ~4-5 hours of agent dispatching. User confirmed Option A (sequential, quality-first).

**Senior briefs feeding this plan:**
- `docs/architecture/plan-b-pumping-mom-deep-dive.md` — CDC milk-storage workflows, bottle splitting, FIFO Home card, schema additions
- `docs/architecture/plan-b-riverpod3-state-pattern.md` — Provider DAG, invalidate-after-write, transaction wrapping sync_state, freezed still blocked
- `docs/architecture/plan-b-visual-design-spec.md` — Stash grid layout, bottle card spec, daily summary 2×2, fl_chart sparkline code

---

## Task list

### B.1 — Foundation (5 tasks)

| # | Task | Files | Tests |
|---|------|-------|-------|
| B1.1 | Migration v2 — add `stash_bottle.thawed_at`, `stash_bottle.parent_bottle_id`, `stash_bottle.source` (CHECK enum), `pump_session.paused_duration_min` | `lib/core/db/migrations/m002_v2.dart`, update `database_provider.dart` to include in `Migrations([...])` | Update `migrations_test.dart` — verify v2 columns exist; verify CHECK enum reject invalid `source` |
| B1.2 | Domain models hand-rolled — Baby, Caregiver, Feed (+ FeedType/Side/Source enums), PumpSession, StashBottle (+ StorageType/BottleSource enums), Diaper (+ DiaperType enum), Sleep (+ SleepLocation enum) | `lib/core/models/*.dart` (7 files) | none — models tested via repo tests |
| B1.3 | BabyRepository + tests (TDD) — insert, getActive, list, softDelete | `lib/features/baby/data/baby_repository.dart`, `test/.../baby_repository_test.dart` | 6 tests |
| B1.4 | CaregiverRepository + tests (TDD) — placeholder "self" caregiver created at first launch | `lib/features/caregivers/data/caregiver_repository.dart`, test | 4 tests |
| B1.5 | `currentBabyIdProvider` (Notifier) + wire Welcome to create Baby row + set selected baby | `lib/features/baby/data/current_baby_provider.dart`, update `welcome_screen.dart` | widget test for welcome flow |

### B.2 — Feed (4 tasks)

| # | Task | Files | Tests |
|---|------|-------|-------|
| B2.1 | FeedRepository + tests (TDD) — insert/update/softDelete/todayFor with sync_state atomicity, optimistic concurrency | `lib/features/feed/data/feed_repository.dart`, test | 10 tests |
| B2.2 | Feed providers — `feedRepositoryProvider`, `feedTodayProvider(babyId)`, derived `feedOzTodayProvider(babyId)` | `lib/features/feed/data/feed_providers.dart` | none (covered via repo) |
| B2.3 | FeedScreen — breast L/R timer with last-side memory + bottle oz/ml with source picker + notes; route `/feed/new` | `lib/features/feed/presentation/feed_screen.dart`, update router | 1 widget smoke |
| B2.4 | Wire Home — replace `_TodayHeroCard` "0 oz fed" placeholder with `feedOzTodayProvider`; replace Today timeline row with last 3 real entries from `feedTodayProvider`; Quick-Log Feed button routes `/feed/new` + update Welcome CTA to "Log a feed now" | `home_screen.dart`, `welcome_screen.dart`, ARB `welcomeStartCta` | smoke |

### B.3 — Pump + Settings (6 tasks)

| # | Task | Files | Tests |
|---|------|-------|-------|
| B3.1 | PumpRepository + tests (TDD) — insert with optional list of stash bottles in same transaction | test | 8 tests |
| B3.2 | Pump providers — `pumpRepositoryProvider`, `pumpTodayProvider(babyId)`, `pumpCountTodayProvider(babyId)` | providers | none |
| B3.3 | PumpSessionScreen — Start/Stop/Pause/Resume timer with persistence across backgrounding via SharedPreferences; side-toggle pills (Both/Left only/Right only); numeric keypad oz inputs with live "Total: X oz"; manual-entry "+ Add past pump" escape hatch; unusual-value soft warn (yellow chip) | screen, route `/pump/new` | widget smoke + 1 unit test for timer persistence |
| B3.4 | Inline bottle-splitting in pump-save flow — preview chips per portion-size setting; long-press chip "Merge with next"; swipe-left "Don't stash this portion"; save creates pump_session + N stash_bottles atomically | extends PumpSessionScreen | unit test for split logic |
| B3.5 | Settings → Pumping section — portion-default selector (One bottle / 2 oz / 4 oz / Ask each time), persists to SharedPreferences | `lib/features/settings/presentation/settings_screen.dart`, route `/settings` (new) | smoke |
| B3.6 | Wire Home — Quick-Log Pump button routes `/pump/new`; "Last pump 3h ago · 5.4 oz" chip below FIFO card | home_screen.dart | smoke |

### B.4 — Stash (6 tasks)

| # | Task | Files | Tests |
|---|------|-------|-------|
| B4.1 | StashRepository + tests (TDD) — insert, listActive (FIFO), markConsumed (with feedId link), markDiscarded, moveStorage (recompute expires_at per CDC), splitBottle, activeCountFor (for 20-cap gate) | `lib/features/stash/data/stash_repository.dart`, test | 12 tests |
| B4.2 | Stash providers — `stashRepositoryProvider`, `stashActiveProvider(babyId)`, `stashCountActiveProvider(babyId)`, `nextFifoBottleProvider(babyId)` | providers | none |
| B4.3 | StashListScreen — 4-col grid of 80×104dp cards with 4dp colored stripe (sage700/honey700/lightError); section header `N of 20 free`; FIFO hint banner top; FAB pair `[+ Log pump] [⏷ bulk-consume]`; "Show history" filter toggle | `lib/features/stash/presentation/stash_list_screen.dart`, route `/stash` | smoke |
| B4.4 | StashBottleDetailSheet — Consume now (primary pill) + Move to fridge / Edit oz (secondary pair) + Mark discarded (tertiary text) + Delete (destructive); recompute `expires_at` on storage change | `lib/features/stash/presentation/stash_bottle_detail_sheet.dart` | smoke |
| B4.5 | ConsumeBottleSheet — pre-filled feed entry create flow; partial-drink leftover prompt → optional new stash_bottle with `source='leftover'` and 2hr countdown | `lib/features/stash/presentation/consume_bottle_sheet.dart` | unit test for partial-drink leftover creation |
| B4.6 | Wire Home — FIFO "next bottle to use" card via `nextFifoBottleProvider`; tap "Use now" → ConsumeBottleSheet; tap "Mark thawing" → moveStorage to fridge | home_screen.dart | smoke |

### B.5 — Diaper (2 tasks)

| # | Task | Files | Tests |
|---|------|-------|-------|
| B5.1 | DiaperRepository + providers + tests | repo/providers/test | 6 tests |
| B5.2 | DiaperScreen — 4 big tappable type tiles (pee/poop/mixed/dry); 1-tap log; route `/diaper/new`; Quick-Log Diaper button wires; Home diaper stat `diaperCountTodayProvider` (with pee/poop split) | screen, home wiring | smoke |

### B.6 — Sleep (3 tasks)

| # | Task | Files | Tests |
|---|------|-------|-------|
| B6.1 | SleepRepository + providers + tests | repo/providers/test | 8 tests (incl `currentSleepProvider` for in-flight) |
| B6.2 | SleepScreen — Start/Stop with persistent in-flight state; location picker (crib/stroller/car/other); manual entry past sleep | screen, route `/sleep/new` | smoke |
| B6.3 | Wire Home — Sleep stat `sleepHoursTodayProvider`; if in-flight sleep, hero shows "Sleeping for 0:42:11" tabular timer | home_screen.dart | smoke |

### B.7 — Daily Summary (4 tasks)

| # | Task | Files | Tests |
|---|------|-------|-------|
| B7.1 | Summary providers — `summaryForDayProvider(babyId, date)` aggregating all 4 stats + micro-trend `summaryDayDeltaProvider` | `lib/features/summary/data/summary_providers.dart` | unit tests |
| B7.2 | DailySummaryScreen — date stepper, range chips, 2×2 tile dashboard with `numeric(40pt)` heroes + sage/honey micro-trends | screen, route `/summary` | smoke |
| B7.3 | fl_chart 7-day sparkline LineChart — lavender700 stroke, gradient fill, no axes, tap tooltip; height 120dp | `lib/features/summary/presentation/feed_oz_sparkline.dart` | smoke (chart renders without throwing) |
| B7.4 | Premium-gated UI — "Generate visit PDF" tile (locked for now — actual PDF in Plan E); 14d/30d range chips show lock icon; tap → paywall sheet stub (placeholder for Plan D RevenueCat) | screen extensions | smoke |

### B.8 — Final gate (1 task)

| # | Task | Files | Tests |
|---|------|-------|-------|
| B8 | `flutter analyze` clean, `flutter test` all pass (~80 tests now), `tool/check_no_exact_alarms.sh` OK, manual smoke flow on Android emu (deferred APK build still OK since toolchain not installed). Tag `plan-b-complete`. | — | — |

---

## Tests at end of Plan B

| Repo / Feature | Tests |
|---|---|
| migrations (v1 + v2) | ~5 |
| baby_repository | 6 |
| caregiver_repository | 4 |
| feed_repository | 10 |
| pump_repository | 8 |
| stash_repository | 12 |
| diaper_repository | 6 |
| sleep_repository | 8 |
| summary_providers | ~6 |
| widget smokes | ~7 |
| **Total** | **~72 tests** (vs Plan A's 10) |

---

## Open questions for user (please answer before full plan write)

1. **In-flight sleep heuristic:** if app force-quits with sleep started but no end, on next launch (a) auto-close at last-known-active timestamp + 1hr (heuristic), (b) prompt user "Sleep still running from N hours ago — Stop when?", (c) silently leave open. Recommend **(b)** but blocking.

2. **Pump portion-default fallback:** what's the default for a brand new user who hasn't visited Settings yet? Brief recommends **"4 oz"** (CDC sweet spot). OK?

3. **Premium gate on Plan B range chips (14d/30d):** Plan D is when RevenueCat actually paywalls. Plan B shows lock icon + paywall sheet stub. **OK to ship the lock without real purchase wire yet?** Tap → "Coming in v1.0 launch" snackbar.

4. **Welcome CTA copy swap:** Plan A's "Start tracking" was placeholder. Plan B introduces `/feed/new` so the CTA finally swaps to **"Log a feed now"** routing there. Confirm?

5. **Multi-baby today:** brief recommends `baby_id` NULL columns now (schema-flag) but UI stays single-baby for v1.0 (multi-baby is Plan D premium). **OK to ship Plan B with no baby switcher UI but schema-ready?**

---

## Recommended next action

Reply with answers to the 5 questions above (or "all defaults OK"), then I write the full Plan B plan (~5000 lines markdown with inline code per task), then dispatch implementer agents sequentially per Option A.
