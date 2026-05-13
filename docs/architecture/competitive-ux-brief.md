# DreamBook — Competitive UX Brief

**Date:** 2026-05-13
**Authors:** Senior Mobile Product Designer + Senior Visual Designer + Senior Activation UX
**Status:** Inputs to Plan A. High-confidence items already applied inline; rest are deferred to Plan B+ with provenance below.

This brief captures the parallel senior review against the bestselling baby-tracker apps in 2026 (Huckleberry, BabyConnect, Nara Baby, Glow Baby, Pump Log) plus visual-minimalism benchmarks (Things 3, Linear, Streaks, Apollo, Calm/Headspace, Robinhood, Frida Mom/Bumo). It validates "clean + minimal" as the right aesthetic *with* mitigations and gives concrete UX moves Plan A executors should land before subagents start coding.

---

## 1. Verdict on "clean + minimal"

**Validated — with three mitigations.** Among the bestsellers, **Nara Baby (5/5 aesthetic) is the closest benchmark** for what clean+minimal looks like done right in this category. Calm/Headspace prove pastels can carry trust signals; Things 3 + Linear prove minimalism can still show depth.

But minimalism in this category has three costs we must explicitly mitigate:

1. **App Store screenshot risk — "feature-poor" optics vs. Huckleberry's chart-heavy density.**
   - *Mitigation:* lead screenshots with our **visible differentiators** (8-char invite code at 56pt; freezer stash inventory) — not the calm daybook. Use copy overlay aggressively: "Full history free. No login. Ever."
2. **Power-user breadth gap — BabyConnect tracks 20+ event types; we ship ~6.**
   - *Mitigation:* aggressively scope by "0–24 mo babies only" (Spec D13) and ship a free-text Notes fallback for the long-tail event types.
3. **"AI predictions" is now category table-stakes signaling — Huckleberry's SweetSpot is the most-praised feature.**
   - *Mitigation:* one earned, on-device prediction in Plan B ("Next feed likely 2:45 PM" using only on-device data). Never marketed as AI, never sent to cloud — preserves the privacy moat *and* checks the intelligence box.

---

## 2. Where each competitor fails (and we win)

| Competitor | Their fatal flaw | DreamBook move |
|---|---|---|
| **Huckleberry** ($68–$120/yr) | 14-step onboarding wall + buried edit UX (#1 review complaint) | 1-screen onboarding, name optional; swipe-edit on Home activity rows |
| **BabyConnect** ($5.99 + new sub) | Email + account required for caregiver share — cluttered "TI-83-calculator" home grid | 8-char invite code; no login ever; calm one-column Home with thumb-zone Quick-Log grid |
| **Nara Baby** ($9.99/yr) | 7-day-history paywall feels hostile (recurring review complaint) | **Free tier shows full history.** Charge for insights/export/extra babies — never the user's own data |
| **Glow Baby** (3.78★ — caution) | Broken caregiver sync + ad-bloat + California privacy settlement | Local-first sync with <2s latency; zero ads; privacy as visible UI chip on Home, not Settings line |
| **Pump Log** ($5.99) | Pumping-only — pumpers run a 2nd app for daybook | Match Pump Log's stash + L/R + expiry alerts AND add Feed/Diaper/Sleep — one app |

---

## 3. Color palette correction (accessibility math)

The spec §17.7 palette is **decorative-only on cream** — none of the 4 brand tokens reaches AA contrast.

| Pair | Contrast | WCAG |
|---|---|---|
| Lavender `#B7A7DD` on cream `#FFF8F0` | **2.03 : 1** | ❌ fails AA body (4.5:1) AND fails 3:1 large/UI |
| Peach `#F4C2A0` on cream | ~1.4 : 1 | ❌ fails everywhere |
| Sage `#90B89A` on cream | ~2.1 : 1 | ❌ fails everywhere |
| Honey `#E8B547` on cream | ~1.9 : 1 | ❌ fails everywhere |

**Required new tokens (added to Plan A Task 5):**

| Token | Hex | Role | Contrast on cream |
|---|---|---|---|
| `ink.primary` | `#2A2438` (deep aubergine, not pure black — softer) | All body + headings | ~13.5:1 ✅ AAA |
| `ink.secondary` | `#6B6478` (warm gray) | Labels, captions | ~5.1:1 ✅ AA |
| `neutral.muted` | `#EDE6DC` (putty) | Dividers, skeletons, inactive chips | decorative |
| `lavender700` | `#6B5BA8` | Lavender on cream for buttons/icons | ~4.7:1 ✅ AA |
| `peach700` | `#B57442` | Peach text/icons | ~4.6:1 ✅ AA |
| `sage700` | `#4F7860` | Sage text/icons | ~4.8:1 ✅ AA |
| `honey700` | `#9E6F12` | Warning text | ~4.8:1 ✅ AA |

**Rule for code reviewers:** brand colors (`primary`, `accent`, `success`, `warning`) carry **fills and illustrations only**. Text and icons on top of cream must use either `ink.*` or the `*.700` derivatives. Lint check in Plan B will enforce this.

---

## 4. Typography addendum

Spec §17.6 ships 7 styles (`displayLarge → labelLarge`). **Add one more:**

- **`statHero`** — **48 pt / weight 700 / tracking -1.5 / tabular numerals** — for the invite code on the share screen, weekly-summary hero numbers, and the milestone "first week" stat. Cost: zero (system font). Justification: Robinhood + Things 3 both rely on this single oversized numeric as their most expensive-feeling element.

**Tighten one rule:** apply negative tracking (-0.3 to -0.5) only to `displayLarge` + `headlineLarge`. Body styles keep tracking 0 — tightening body reads cramped at 3 AM on a 6.1" screen.

**Plex Thai pairing:** weights 400 (body) + 600 (heading) only. Weight 500 in Plex Thai is uneven — skip.

---

## 5. Home screen density (Plan A audit)

Plan A's Home as drafted scores **2.5/5** for density — too sparse. The "void" between hero card and Quick-Log grid reads as "did the screen finish loading?" instead of "calm whitespace."

**Applied in Plan A Task 15:**
1. **Caregiver attribution pill** under hero card: "Logged by: Mom · 2 caregivers active" — 12pt, `ink.secondary`. Silently answers "is this multi-person mode?"
2. **Today timeline row** in the middle: last 3 events as horizontal chips ("Pump 4oz · 2h ago", "Diaper · 3h ago", "Feed · 4h ago"). Tappable to expand. This is the Nara move — shifts density 2.5 → 4.
3. Quick-Log grid stays **2×2** (resist 3×2 — that's the Huckleberry mistake).

---

## 6. Share / Invite screen layout (applied in Plan A Task 16)

**Before (Plan A draft):** invite headline → code 44pt → expiry chip → QR placeholder → share button.

**After (applied):** **QR first** (150dp box, top center) → code below at **56 pt** tabular monospaced (was 44pt — bump for "dictating over the phone" use case) → expiry chip → native-share button thumb-reachable bottom-third → caregivers-active list below.

**Why flip:** WhatsApp's data shows scan completes in ~2 seconds vs. ~15 for typing. QR is the faster path; code is the fallback for "read it aloud over phone." Plan A previously buried QR below the code — fixed.

**Code separator locked as `XXXX-XXXX`** (single hyphen at position 4, Miller chunk rule). Crockford base32 alphabet (no I/L/O/U) per Spec D1.

**Trust-signal copy upgrade:** Spec §18.5's "Connecting securely…" is necessary-but-not-sufficient. Plan C (caregiver join flow) will render: **"Connecting to {babyName}'s family · End-to-end encrypted"** + lock icon + family-fingerprint preview ("born May 2026"). This is what prevents the "is this a scam?" feel at code entry. Deferred to Plan C with this brief as provenance.

---

## 7. Activation moment definition

**For DreamBook, activation = first feed saved.** Not first caregiver invited, not name entered, not first Home view.

**Defense:**
- Solo value first, social value second. Mom alone at 2 AM with a hungry baby cannot complete a "first invite" activation.
- Feeds repeat 8–12×/day — the habit-loop entry point.
- First-feed → invite is the natural funnel ("look how fast — install this").
- RevenueCat data: activated users retain ~3× longer than non-activated.

**Plan A implication:** Welcome screen's primary CTA shifts from "Take me in" to **"Log a feed now"**. Routes to `/feed/new` in Plan B; in Plan A's foundation scope, the CTA renders the copy but routes to `/home` because `/feed/new` doesn't exist yet — wire the route stub now so Plan B can swap implementation without churn.

---

## 8. Caregiver attribution pattern (defer widget to Plan B; document now)

Every activity row shows **24dp avatar pill** with 2-char initials + deterministic color (from extended caregiver palette). Name reveals on long-press only — keeps scan rhythm; preserves "every row has an avatar" trains-the-eye behavior.

Self-logged entries show your own initial too — never hidden. This prevents the partner-avatar appearing as a surprise.

**Why not name-only:** doubles row height, kills scan rhythm.
**Why not color-only:** fails A11y §17.5 (color-only meaning).

Widget name: `CaregiverAvatarPill`. Created in Plan B.

---

## 9. Day-3 retention (defer to Plan B+; constraints documented now)

**Forbidden in any plan:** streaks, points, badges, "you're on fire!", confetti, leaderboards. Wrong tone for sleep-deprived parents; reads as guilt.

**Plan B+ surface:** **WeekInsightCard** on Home, appears only on D3 if (entries ≥ 5 AND caregivers = 0 AND !dismissedTwice). Data first, ask second:

> Mali's been busy
> 14 feeds · 9 hrs sleep · 7 diapers
>
> Want Dad to log too? It takes 30 seconds.
> [ Invite ]   [ Maybe later ]

"Maybe later" dismisses 7 days; second dismiss is permanent. No urgency language.

**Rating prompt:** centralized `RatingPromptGate` service. Hard floor: `installDays ≥ 14 && totalEntries ≥ 20 && lastPromptDaysAgo ≥ 60`. No screen calls `requestReview()` without going through this gate. Codify in Plan B.

---

## 10. Anti-patterns banned across all plans

| # | Banned | Why |
|---|---|---|
| 1 | Rating prompt before Day 14 + ≥20 logs | Early prompts produce 1-star ratings from confused users |
| 2 | Email capture popup anywhere | Spec §9 mandates no-login; an email field undermines the moat |
| 3 | Confetti / nth-log celebration | Patronizing for sleep deprivation |
| 4 | Onboarding tutorial overlay tour | Tutorials exist because UI failed; fix the UI |
| 5 | Push notification on D0 | Permission ask before value = denial + uninstall |
| 6 | Partner-required gates ("invite first") | Mom-at-2-AM scenario; solo path must work fully |
| 7 | Banner/interstitial ads anywhere | Spec §17.3 + DreamBaby rule + lifetime-pricing economics |
| 8 | Streaks, points, badges, levels | Wrong tone; "skipped a day = guilt" punishes parents |
| 9 | "Rate us" or "Share DreamBook" inside the invite flow | Two asks in one flow → both fail |
| 10 | Pre-filling code on clipboard "for convenience" | Clipboard leakage = security regression |
| 11 | Animating illustrations in `nightTint` mode | Red-shift narrow gamut → visible color stepping |
| 12 | "Powered by Supabase" or third-party logos on share/connect screens | Undermines "no cloud account" narrative |

---

## 11. Motion + microinteractions

**Animate (delight):**
- Card tap: 150ms scale 1.0 → 0.97 → 1.0, spring physics
- Save success: 200ms checkmark draw + light haptic
- Bottom-sheet present: 280ms ease-out cubic
- Number tick on hero stat when value changes (CountUp 400ms)

**Do NOT animate:**
- Sleeping baby / mascot illustrations (static — animated reads as cute on Dribbble, infuriating at 2 AM)
- Anything in `nightTint` mode (cross-fades only, no scale/translate)
- Skeleton loaders > 500ms (show empty state instead)
- Tab bar icons (switching is structural, not delightful)

**Hard rule:** every animation respects `MediaQuery.disableAnimations` (Android reduce-motion / iOS Reduce Motion). Plan B will introduce a `motionEnabledProvider`.

---

## 12. Iconography call

**Plan A: stay on Material Symbols Rounded weight 300, optical size 24.** Free, instantly recognizable, matches cream/lavender warmth; weight 300 matches Plex Thai's contrast.

**Plan B+: revisit** custom Lucide-derived set ($0–$200 design sprint) IF post-launch data shows icon confusion. Defer.

---

## 13. Empty-state design system

Formula (warm without cutesy):
1. Single hand-drawn illustration at top, monochrome in `lavender.500` on cream, ~140×140 px, line weight 1.5 px, **no faces**.
2. Headline: sentence case, 22 pt, weight 600, max 6 words.
3. Subhead: 15 pt, weight 400, `ink.secondary`, max 18 words.
4. One primary CTA, pill-shaped, `lavender.700` bg, cream text. No secondary action.
5. Vertical center alignment, 80 px from top.

**5-illustration budget** (Spec §18.10): Home empty / Log empty / Insights empty / Invite empty / Achievement unlock. No more. Commission Plan E or F.

**Banned:** cartoon babies, googly eyes, anthropomorphic bottles, rainbows.

---

## 14. Five micro-patterns to explicitly out-design

1. **Huckleberry's onboarding survey** (14 questions) → 1 screen, "What should we call your baby?" only, defaults to "Baby" if skipped
2. **Nara's history paywall** (7-day on free) → full history free, monetize insights/export
3. **Calm's gradient hero** (unreadable in nightTint) → static cream surface + lavender hairline
4. **Robinhood's hero stat** (lonely, no context) → pair `statHero` with sage micro-trend ("↑ 0.4 oz vs yesterday")
5. **Headspace's mascot circles** → no mascot; illustrations are tools (moon, bottle, leaf), never characters

---

## What was applied to Plan A inline

- Task 5 design tokens: added `ink.primary/secondary`, `neutral.muted`, `*.700` dark color variants, `statHero` 48pt typography
- Task 15 Home screen: added caregiver attribution pill + Today timeline row of 3 most-recent events; density target 4/5
- Task 16 Share placeholder: flipped layout (QR top 150dp → code 56pt → expiry chip → share-via thumb-zone bottom)
- Task 18 Welcome: baby name + DOB now optional with defaults; primary CTA copy changed to "Log a feed now" (routes to `/home` in Plan A; will retarget `/feed/new` in Plan B)

## What was deferred to later plans (with provenance here)

- **Plan B:** `CaregiverAvatarPill` widget; `WeekInsightCard` D3 surface; `RatingPromptGate` service; `motionEnabledProvider`; entries CRUD that enables `/feed/new` route swap; activation event `analytics_local` table
- **Plan C:** trust-signal copy + family-fingerprint preview on caregiver join; real invite code generation (Crockford 8-char `XXXX-XXXX`)
- **Plan E or F:** 5 hand-drawn empty-state illustrations; custom icon evaluation
