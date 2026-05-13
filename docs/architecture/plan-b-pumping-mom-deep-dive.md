# Plan B Senior Brief 1 — Pumping Mom UX Deep Dive

**Researcher:** Senior UX, postpartum / pump-mom workflows
**Date:** 2026-05-13

---

## TL;DR — MUST-LAND in Plan B (deal-breakers)

- **One-thumb Start → Stop → Save in ≤6 taps, never blocked by modals, with manual-entry escape hatch.**
- **Inline bottle-splitting at save time with a sticky portion-size default** (CDC says 2-4 oz; one-bottle-per-session is wrong for the majority).
- **FIFO "next bottle to use" card on Home screen — free tier** (competitor's strongest paid feature, ours for free).
- **Storage-transition recompute** (`thawed_at`, `expires_at`) with CDC-correct math — freeze→fridge = +24h, fridge→room/warm = +2h, partial-bottle leftover = +2h room-temp countdown. Free tier.
- **Schema-flag now for `thawed_at`, `parent_bottle_id`, `source`, `baby_id`** — adding these to `stash_bottle` post-launch means a migration nightmare; cost to add now is one column-spec each.

## Schema additions required (migration v2)

`stash_bottle` table — add 3 columns:
- `thawed_at TEXT NULL` — distinct from `frozen_at`; required for fridge 24h countdown
- `parent_bottle_id TEXT NULL REFERENCES stash_bottle(id) ON DELETE SET NULL` — split lineage
- `source TEXT NOT NULL DEFAULT 'pump' CHECK (source IN ('pump','collector','split','leftover'))` — wearable-collector + partial-bottle leftover support

`pump_session` table — add:
- `paused_duration_min INTEGER NOT NULL DEFAULT 0` — for Start/Pause/Resume support

## The pump session — real-world taps (4-6 total)

1. Open → tap FAB "Pump" → land on screen with giant Start button bottom 40%
2. Tap Start → timer runs; `started_at = now()`. Side-toggle pills (Both/Left only/Right only) above.
3. (Pump for 15-25 min in the physical world)
4. Tap Stop → numeric keypad pops, oz fields auto-focus. Live "Total: 6.3 oz" above.
5. Save-to-stash toggle (sticky default) — preview chips `[4.0 oz] [2.3 oz]` per portion-size setting
6. Tap Save → done

**Never block save with confirmation modals.** Soft-warn unusual values (single side >12oz, total >20oz) with inline yellow chip, allow save.

**Don't pre-fill oz from last session.** Pump output varies session-to-session; pre-filling teaches mindless saves and corrupts the dataset. Show ghost-text "L: ~3.2 avg" as a sanity cue, not a value.

**Pause/resume:** tap timer to pause (re-latch flange, baby cries). `paused_duration_min` accumulates.

**Forgot-to-stop heuristic:** if timer running >60min in background, fire inexact notification with Stop action.

**Manual entry escape hatch:** `+ Add past pump` link → 3-field sheet (started_at stepper default "1hr ago", duration 20, oz L/R).

## Freezer stash — bottle splitting

CDC + WIC + Mayo advise 2-4 oz portions. Plan A's "one session = one stash bottle" is wrong for majority of EP moms.

**Recommended approach:** Settings → Pumping → "How do you store?" with options:
- "One bottle per session"
- "Split into 2 oz portions" (default)
- "Split into 4 oz portions"
- "Ask me each time"

At save time, save-to-stash toggle expands to show portion preview chips. Long-press chip → "Merge with next". Swipe-left chip → "Don't stash this portion."

Post-hoc splitting from Stash screen: tap bottle → detail → "Split this bottle" → numeric splitter; children inherit `pumped_at` for FIFO integrity, `parent_bottle_id` set.

## FIFO consumption — the killer feature (FREE tier)

Home screen shows: **"Next bottle to use: 4.0 oz pumped May 8 (5 days old)"** with "Mark thawing" + "Use now" actions. No competitor surfaces this on Home — wedge.

**Consume flow:** Stash → tap "Use" → confirm sheet pre-filled (feed_type=breastmilk_bottle, oz=bottle.oz, started_at=now). Edit oz for partial drink. Tap Save → creates `feed` row with `from_stash_bottle_id`, marks bottle `consumed_at=now()`, `consumed_feed_id=feed.id`.

**Mark thawing → storage transition:** freezer → fridge, `thawed_at=now()`, `expires_at = now() + 24h`. Per CDC "use within 24h from completely thawed."

**Partial-drink leftover** (baby drank 2.5 of 4 oz): create feed with actual drank amount, mark bottle consumed, prompt "Save remaining 1.5 oz? [Discard] [Save 2hr countdown]". If saved: new `stash_bottle` with `oz=1.5`, `source='leftover'`, `storage='room'`, `parent_bottle_id` set, `expires_at = now() + 2h`. Per CDC + ABM Protocol #8.

## Expiry edge cases

- **6mo frozen → soft warning, NOT auto-discard.** CDC: 6mo best, 12mo acceptable. Show 🔴 + banner "past 6mo CDC ideal but usable up to 12mo."
- **Fridge 4-day countdown:** display ">3 days" / "18h left" / "4h left". Color 🔴 at <12h.
- **Room temp 4hr / leftover 2hr:** to-the-minute countdown.
- **Used vs discarded:** separate states. `consumed_at` (used) vs `discarded_at` (thrown). Discard ratio >15% → surface tip "Consider freezing smaller portions."

## Anti-patterns to forbid in Plan B

1. Bright white screens at 3 AM (mandatory dark/nightTint)
2. Dial-style time pickers with small numbers (use steppers + numeric keypad)
3. Hiding the "last pump X ago" indicator (always visible on Home)
4. Forcing both-side input (side-toggle pills hide unused field)
5. Modal-locked Save (no confirmation between Stop and Save)
6. No cross-device export (defer to Plan C QR-import)
7. Single-baby schema lock (baby_id NULL columns now; UI single-baby for v1)
8. No wearable-collector entry (add `source='collector'` option)

## Three competitor-paid features we give FREE

1. **FIFO Home card** (Pump Log charges $8.99 for Countdown Calculator)
2. **Inline + post-hoc bottle splitting** (neither Pump Log nor ParentLove does this well)
3. **CDC-compliant storage transitions** (medical correctness — never paywall)

Premium adds: bottle count >20, expiry push notifications, CSV export.

## Required UI flows for Plan B

- `PumpSessionScreen` — Start/Stop/Save, side-toggle, manual entry, save-to-stash inline split
- `StashListScreen` — FIFO sort, color-coded grid, swipe Use/Discard
- `StashBottleDetailSheet` — Consume/Move to fridge/Split/Edit/Delete actions
- `HomeScreen` — Next-bottle FIFO card (replace existing Today timeline placeholder?)
- `Settings → Pumping` — portion-default config
- `ConsumeBottleSheet` — chains feed creation, handles partial-drink leftover
