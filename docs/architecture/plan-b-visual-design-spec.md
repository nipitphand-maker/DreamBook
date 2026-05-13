# Plan B Senior Brief 3 — Visual Design Spec

**Author:** Senior Mobile UI Designer
**Date:** 2026-05-13

---

## TL;DR — Visual non-negotiables

- **Text/icon on cream MUST use `AppColors.inkPrimary`, `inkSecondary`, or any `*.700` derivative** — never raw brand 500 (decorative fills only).
- **Spacing is 8-grid, no exceptions** — only sub-8 value allowed is the 4dp bottle-card stripe.
- **Bottle card color stripe is dual-channel** — color + storage icon (A11y §17.5).
- **Hero numerics use tabular figures** via `AppTypography.numeric` or `statHero` — never default proportional digits in stat tiles, oz cards, or chart tooltips.
- **Primary actions in bottom thumb-zone** (bottom 30% of screen).
- **Three themes first-class** — every color resolves to light/dark/nightTint sibling; no hardcoded hex in widgets.

## Freezer Stash screen — key specs

**Layout:** 393×852dp baseline, 56dp app bar, FIFO hint card (64dp), section header `18 of 20 free`, 4-column bottle grid (80×104dp cards, 16dp gutters), bottom thumb-zone FAB pair `[+ Log pump] [⏷ bulk-consume]`.

**Bottle card (80×104dp):**
- AppRadii.sm (12dp), elevation level1, cream surface
- **4dp left edge stripe** colored by expiry band:
  - 🟢 Fresh (<1mo): `AppColors.sage700` (#4F7860)
  - 🟡 Aging (1-4mo): `AppColors.honey700` (#9E6F12)
  - 🔴 Near-expiry (<1mo to `expires_at`): `AppColors.lightError` (#B3261E)
- Top: `4.5 oz` — `AppTypography.numeric(size: 24, weight: w700)` ink.primary
- Bottom: `❄ 5d` — labelLarge 14pt ink.secondary + storage icon (ac_unit/kitchen/coffee) matching stripe color
- Consumed/discarded bottles: removed from grid by default; behind `⋯ filter → Show history` toggle, 48% opacity + dashed border

**Bottom sheet (on bottle tap):**
- Primary: **Consume now** — full-width 56dp pill, lavender700 bg + cream text (5.6:1 AA)
- Secondary pair: **Move to fridge** + **Edit oz** — 48dp outlined buttons
- Tertiary: **Mark as discarded** — text button
- Destructive: **Delete** — error700 text, undo-snackbar (no confirm dialog)

**Free tier cap (18/20):**
- Section counter color shifts honey700
- Info chip below FIFO banner: `ⓘ 2 bottles until you hit the free limit. Upgrade →`
- At 20/20 → paywall bottom sheet with 3 escape hatches: `Try free 7 days` / `Save without stash` / `Delete an old one`

**FIFO hint placement:** Banner at top, dismissible-but-persistent. Returns when oldest fresh bottle is <14 days from aging.

**Empty state:** Material Symbols Rounded `Icons.ac_unit` 80sp lavender700 + "Your freezer is empty" + "Log first pump" primary pill.

## Daily Summary screen — key specs

**Layout:** date stepper (`‹ Mon May 11, 2026 ›`), 4-chip range selector `[Day] [7d] [14d 🔒] [30d 🔒]`, 2×2 dashboard tiles (160×132dp), 7-day fl_chart sparkline card (120dp tall), premium-gated "Generate visit PDF" CTA.

**2×2 tiles (160×132dp, AppRadii.md, cream, elev1):**

| Position | Icon | Hero | Label | Micro-trend |
|---|---|---|---|---|
| TL | `local_drink` lavender700 | 18.5 (40pt numeric w700) | `oz feed` | `↑ 0.4 vs Sun` sage700 |
| TR | `water_drop` peach700 | 7 | `diapers` | `5 pee · 2 poop` ink.secondary |
| BL | `nightlight` lavender700 | 13.5 | `hrs sleep` | `↓ 0.6 vs Sun` honey700 |
| BR | `ac_unit` sage700 | 3 | `pumps · 20 stash` | `↑ 1 vs Sun` sage700 |

**Micro-trend rule:** sage700 for "directionally good," honey700 for "directionally cautious," ink.secondary for neutral splits. NEVER lightError red for trend (reserved for true alerts).

**Mini-chart (fl_chart 1.x LineChart):**
- 120dp tall card, full-width-16-inset margin
- Single lavender700 stroke 2dp wide, curved with `preventCurveOverShooting: true`
- Linear gradient fill lavender700→transparent 0.18 alpha
- No axes, no grid, no borders
- Tap tooltip: `Sun · 18.1 oz` (labelLarge, dark bg)

**Wet/soiled diaper:** in tile micro-trend slot `5 pee · 2 poop`. Drill-down screen has stacked horizontal bars (peach700 pee, honey700 poop) — for visit PDF data.

**Date picker:** stepper (`‹ ... ›`) with tap-center to open Material calendar as fallback (NOT default). 48dp arrows. Free tier disables at install-day-90. Premium infinite.

**Empty stat rule:** Show `—` (em-dash) for zero-entry days — except diaper tile, which shows `0` if diapers were logged historically (real "0 diapers today" is a pediatric flag).

## Cross-cutting

**Motion:**
- Card tap: 150ms scale 1.0→0.97→1.0 spring + `selectionClick` haptic
- Save: 200ms checkmark + `lightImpact` haptic + new card slide-in 280ms ease-out
- Date switch: 180ms cross-fade of tile values, no slide
- nightTint mode: cross-fade only (no scale, no slide)
- All respect `MediaQuery.disableAnimations`

**Loading:**
- <80ms → blank container (don't render skeleton — flicker)
- 80-500ms → skeleton with neutral.muted rounded rects, no shimmer
- 500ms+ → still skeleton, log perf warning

**Error:**
- Inline retry card (NOT full-screen overlay) — 160dp tall: `⚠ Couldn't load your stash` + `[Retry]`
- Each tile shows micro-error individually + single bulk retry chip below grid

## 6 Plan B anti-patterns to forbid

1. Never use `ColorScheme.primary` (lavender500) for stash bottle text/stripe/hero — fails AA. Use `lavender700` or `inkPrimary`.
2. Never use `GridView.builder` infinite scroll for stash — must be `SliverGrid` with count cap (free-tier 20).
3. Never animate stat-tile hero numbers in nightTint (red-shift gamut + CountUp causes step banding). Cross-fade only.
4. Never use full 48pt `statHero` in 160dp tile — overflows. Use `numeric(size: 40, weight: w700)`.
5. Never use raw `#90B89A` lightSuccess for "fresh" stripe — fails AA. Use `sage700`.
6. Never use `showDatePicker()` modal as primary date control — fails one-thumb. Stepper-with-tap-to-open-calendar.

## fl_chart 1.x code reference

```dart
LineChart(
  LineChartData(
    minY: 0,
    lineTouchData: LineTouchData(
      handleBuiltInTouches: true,
      touchTooltipData: LineTouchTooltipData(
        getTooltipColor: (_) => AppColors.inkPrimary.withOpacity(0.92),
        tooltipRoundedRadius: AppRadii.xs,
        getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
          '${_dow(s.x.toInt())} · ${s.y.toStringAsFixed(1)} oz',
          AppTypography.labelLarge(color: AppColors.lightSurface),
        )).toList(),
      ),
    ),
    titlesData: const FlTitlesData(show: false),
    borderData: FlBorderData(show: false),
    gridData: const FlGridData(show: false),
    lineBarsData: [
      LineChartBarData(
        spots: data,
        isCurved: true,
        preventCurveOverShooting: true,
        color: AppColors.lavender700,
        barWidth: 2,
        dotData: const FlDotData(show: false),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.lavender700.withOpacity(0.18),
              AppColors.lavender700.withOpacity(0.0),
            ],
          ),
        ),
      ),
    ],
  ),
)
```
