# DreamBook — Design Spec

**Draft date:** 2026-05-13
**Status:** Spec draft (no implementation yet — per user)
**Owner:** nipitphand
**Companion app:** DreamBaby (Flutter baby-sleep-aid, pre-Play Store QA)

---

## 1. Executive Summary

**DreamBook** is a privacy-first baby daybook for new parents, with first-class focus on **pumping moms** and **multi-caregiver coordination without an account**. It tracks feeds, pump sessions (with freezer-stash inventory), diapers, sleep, and vaccinations on-device, and lets a mom invite her partner, grandma, or nanny via a 6-digit code so they can log entries while she's resting — all end-to-end encrypted, no email, no password.

DreamBook is the second app in the **Niyoko Studio** baby line and a sibling to **DreamBaby**. The two apps are released independently, share a `Baby Profile` on-device via platform IPC (Android `FileProvider`, iOS App Groups), and deep-link to each other. The bundling story ("DreamBaby + DreamBook = your night-in-one") becomes a cross-promotion and RevenueCat offering down the road.

**Target launch:** Android first, iOS 1–2 months later, mirroring DreamBaby.
**Target build window for v1.0:** 7–11 weeks.

---

## 2. Product Vision & Positioning

### 2.1 Target user

**Official target age range:** 0–24 months (newborn through toddler). Older children explicitly out of scope — reduces COPPA exposure and keeps the product focused. [D13]

| Persona | Primary need | Why DreamBook |
|---------|-------------|---------------|
| **Pumping mom (0–6 mo baby)** | Log L/R oz, manage freezer stash, hand off to caregivers | Pumping-specialist UX + share-without-login + privacy |
| **Multi-caregiver household** | Mom + partner + nanny + daycare logging the same baby | Invite code, no signup, real-time sync (when active) |
| **Privacy-conscious parent** | Doesn't want baby data on Big Tech servers | E2E encrypted, on-device-first, no account |

### 2.2 Positioning statement

> *"DreamBook is the baby daybook that lets your whole family log feeds, pumps, and diapers in real-time — without anyone making an account. Your baby's data stays on your phones, encrypted end-to-end."*

### 2.3 Hooks that close the deal

1. **"No-login share"** — invite code 6 digits, like AirDrop / Zoom meeting ID, no email anywhere
2. **Pumping freezer-stash inventory** — kills Pump Log ($5.99) by adding share + diaper + sleep
3. **Visit Summary PDF** — premium hook that pediatricians will love (and moms will brag about)
4. **Bilingual EN/TH from day 1** — the only modern Thai-language baby tracker

---

## 3. Competitive Landscape

| App | Pricing | Family share | Multi-baby | USP | Weakness |
|-----|---------|--------------|------------|-----|----------|
| Huckleberry | $99/yr | Premium | Premium | AI predictions | Expensive, login required |
| BabyConnect | $5.99 one-time | **Free** | Free | Family share gold standard | Dated UI |
| Baby Tracker (Nighp) | Free + ads | None | 1 baby | Free, simple | No share, no modern UX |
| Glow Baby | $59.99/yr | Premium | Premium | Community + tracker | Sales-y, ad-heavy |
| Nara Baby | $9.99/yr | Premium | Premium | Beautiful UI | 7-day history on free |
| Pump Log | $5.99 one-time | None | None | Pumping niche specialist | No feed/diaper/sleep |
| Sprout Baby | $4.99 one-time | None | None | Cheap | Basic |

### 3.1 Where DreamBook wins

- **Caregiver share is FREE and login-free** (BabyConnect-killer, while BC has dated UI)
- **Pumping-specialist depth + general daybook breadth** (Pump Log + BabyConnect in one)
- **Privacy + E2E encrypted** (no competitor offers this credibly)
- **90-day history free** (more generous than Nara 7-day, Huckleberry 30-day)
- **Thai language at launch** (no modern competitor here)

---

## 4. Phased Roadmap

| Phase | Scope | Target |
|-------|-------|--------|
| **v1.0 MVP** | Feed, Pump+Stash, Diaper, Sleep, Daily Summary, Caregiver Share, Vaccination Log, Visit Summary PDF, Multi-baby (premium), EN+TH | 7–11 weeks |
| v1.1 | Growth + percentile, Milestone, Med tracker, Photo per entry, AI insights, Solids log (lite), CSV export | +4 weeks |
| v1.2 | **DreamBaby bridge (deep)** — shared Baby Profile via platform IPC, "lullaby suggestions after feeds", unified timeline showing DreamBaby Sleep Log | +2 weeks |
| v1.3 | Apple Watch / Wear OS companion, web dashboard, advanced AI (Huckleberry-style sweet-spot prediction) | TBD |

v1.0 ships independently of DreamBaby. v1.2 requires DreamBaby launched and an agreed cross-app data contract.

---

## 5. MVP Feature Spec (v1.0)

### 5.1 Feed

- **Breast:** L/R timer with last-side memory, duration tracked, end-time logged
- **Bottle:** oz or ml (locale-aware default: oz USA / ml TH), source = `breastmilk` or `formula`; if `breastmilk`, optional "from freezer stash" → auto-decrements stash
- **Quick-log button** on Home: 1-tap to start the most-recent feed type
- **Notes field** per entry (free text, 240 chars)

### 5.2 Pump

- Fields: `left_oz`, `right_oz`, `total_oz` (computed), `duration_min`, `started_at`
- **Auto-create freezer stash bottles** when pump session saved (configurable: store all / store some / discard)
- Locale-aware unit (oz / ml)

### 5.3 Freezer Stash

- Bottle records: `volume`, `pumped_at`, `frozen_at`, `expires_at` (default 6 months frozen, 4 days fridge)
- **Expiry alert** (inexact, T-3 days) — *uses inexact alarms only per DreamBaby notification rule*
- Free tier cap: **20 bottles** active; premium unlimited

### 5.4 Diaper

- Type: `pee`, `poop`, `mixed`, `dry`
- Optional: color/consistency (collapsed by default — power-user toggle)
- 1-tap log

### 5.5 Sleep

- `started_at`, `ended_at`, `duration_min` (computed), location (`crib`, `stroller`, `car`, `other` — optional)
- **Does not duplicate DreamBaby's Sleep Log;** v1.0 stores locally; v1.2 merges DreamBaby's data into the timeline read-only

### 5.6 Daily Summary

- Top of Home screen: total feed oz, # diapers (pee/poop split), total sleep hrs, # pumps, # stash bottles
- Day picker (today / yesterday / pick date — limited to last 90 days on free)
- Weekly mini-chart sparkline (premium)

### 5.7 Caregiver Share (the differentiator)

#### Flow
1. Mom: "Invite caregiver" → app generates **8-char Crockford base32 code** (e.g., `MK2-9HFX4`, no ambiguous chars like `0/O/1/I`) valid 1 hour, single-use [D1]
2. Caregiver opens DreamBook (first-time onboarding), taps "I have a code" → enters code or scans QR → connected
3. Caregiver sees baby data, can log entries (write permission unless mom set read-only)

#### Permission levels (premium)
- **Read-only:** view but cannot log
- **Editor:** view + log entries
- **Admin:** view + log + invite more (only mom by default)

Free tier: editor only, no permission control. Premium unlocks read-only / admin.

#### Activity feed
- "Dad logged a 4 oz bottle at 2:14 PM" appears in shared timeline with caregiver attribution

### 5.8 Vaccination Log (lite)

- Manual entry only: vaccine name, date, clinic name, notes
- **No automated schedule** (liability — schedules differ per country, may change)
- Pre-filled vaccine name suggestions per locale (CDC list USA, MoPH list TH)

### 5.9 Visit Summary PDF (premium hook)

- Button "Generate Pre-visit Report" → PDF with:
  - **Default range: last 7 days** (clinical window per pediatric advisor); toggle 14 / 30 days [D5]
  - Daily feed total oz + chart
  - **Wet diaper count + soiled diaper count per day** (key newborn feeding-adequacy indicator)
  - Sleep totals + **longest sleep stretch per day**
  - Latest weight/height (v1.1)
  - Vaccination history with last-dose dates
  - Optional "Concerns to discuss" parent-entered free-text section
  - Footer disclaimer: *"Parent-recorded; not a substitute for medical examination."*
- Share via system share sheet → email to pediatrician

### 5.10 Multi-baby

- Free: 1 baby
- Premium: unlimited (twin support — same DOB, separate logs)
- Baby switcher in app bar

---

## 6. Architecture

### 6.1 Tech stack (matches DreamBaby pattern)

| Layer | Choice | Reason |
|-------|--------|--------|
| App framework | Flutter | Code share with DreamBaby possible, cross-platform |
| State | Riverpod | Same as DreamBaby |
| Local DB | `sqflite_sqlcipher` | Encrypted at rest; same DreamBaby pattern |
| Routing | `go_router` | Same |
| L10n | `flutter_localizations` + `intl` + ARB | Same |
| Subscriptions | RevenueCat (`purchases_flutter`) | Same; cross-app bundle offering possible |
| Local notifications | `flutter_local_notifications` (inexact only) | **Hard rule per DreamBaby memory** |
| Sync backend | Supabase (free tier → paid as we grow) | Postgres + realtime + row-level security |
| Crypto | `cryptography` Dart package | E2E AES-GCM with X25519 key exchange |
| Secure key storage | `flutter_secure_storage` (Keychain iOS / EncryptedSharedPreferences Android) | Hardware-backed family key storage, not sqflite [D2] |
| Backend region | Supabase `ap-southeast-1` (Singapore) | TH latency win; USA latency acceptable [D3] |
| PDF export | `pdf` + `printing` | For Visit Summary |
| Charts | `fl_chart` | Daily/weekly summaries |

### 6.2 Folder structure (scaffolded 2026-05-13)

```
/lib
  /features
    /onboarding /home /feed /pump /diaper /sleep /stash
    /share /summary /vaccination /visit_report
    /subscription /settings /dreambaby_bridge
  /core
    /db /sync /crypto /router /theme
  /l10n
/assets /icons /images
/android /ios
/docs/superpowers/specs /architecture /marketing
```

### 6.3 Data model (key tables in encrypted sqflite)

```
baby (id, name, dob, sex, photo_path)
caregiver (id, display_name, device_id, role, joined_at)
feed (id, baby_id, type, side, oz, source, started_at, ended_at, note, logged_by)
pump_session (id, baby_id, left_oz, right_oz, duration_min, started_at, logged_by)
stash_bottle (id, baby_id, pump_session_id, oz, pumped_at, frozen_at, expires_at, consumed_at)
diaper (id, baby_id, type, color, consistency, occurred_at, note, logged_by)
sleep (id, baby_id, started_at, ended_at, location, note, logged_by)
vaccination (id, baby_id, vaccine_name, date, clinic, note)
sync_state (record_id, table, version, updated_at, dirty)
```

Every row has `logged_by` = caregiver id → attribution in activity feed.

### 6.4 Sync architecture (E2E encrypted relay)

```
[Mom phone]  --encrypted blob-->  [Supabase]  <--encrypted blob--  [Dad phone]
   |                                  |                                  |
   AES-GCM key                  stores only                       AES-GCM key
   (never sent)                ciphertext                        (received via
                                                                  invite handshake)
```

#### Invite handshake
1. Mom's app generates **family key** `K_family` (random 256-bit AES key) on first launch
2. Invite: app derives **invite code** = `base32(HKDF(K_family, "invite"))[:6]` + 1-hour TTL nonce stored in Supabase
3. Caregiver enters code → app fetches nonce + encrypted `K_family` from Supabase (wrapped with code-derived key) → unwraps `K_family` → both phones share the key
4. From now on, **all rows are AES-GCM encrypted client-side** before upload; Supabase stores only ciphertext + row metadata (table name, version, updated_at)

#### Conflict resolution
- Last-write-wins per `(record_id, table)` via `version` column
- Soft delete (tombstone row) — no hard delete from Supabase to avoid lost-update races

#### Offline-first
- Local sqflite is **source of truth**
- Sync worker runs on:
  - App resume
  - WorkManager (Android) / BGTaskScheduler (iOS) — **inexact** background sync ~ every 15–30 min
  - User pull-to-refresh on Home

#### Why Supabase (not self-host on Hetzner)
- Auth/realtime/RLS out of the box
- Free tier: 50k MAU, 500MB DB, 2GB bandwidth → covers thousands of families before paying
- One-person ops is achievable
- Hetzner self-host = revisit at v2.0 scale if economics demand

### 6.5 DreamBaby bridge (v1.0 light → v1.2 deep)

#### v1.0 (light)
- DreamBook detects DreamBaby installed (`Intent.queryIntentActivities` Android / Universal Links iOS)
- Deep-link button on Home: "Open DreamBaby Player"
- Read DreamBaby Sleep Log via:
  - **Android:** `FileProvider` with explicit content URI exposed by DreamBaby
  - **iOS:** App Group shared container `group.studio.niyoko.baby`
- Display DreamBaby's sleep entries in DreamBook's daily timeline (read-only, marked "via DreamBaby")

#### v1.2 (deep)
- Shared **Baby Profile** record (name, DOB, photo) — either app can update, the other reflects
- DreamBaby reads DreamBook feed data → suggests "ลูกอิ่มแล้ว ลอง Lullaby 03"
- DreamBook reads DreamBaby Bedtime Routine → shows in Visit Summary PDF
- Requires DreamBaby app update to expose the data contract (coordinate releases)

---

## 7. Monetization

### 7.1 Free tier (intentionally generous — share is FREE to drive the differentiator)

| Feature | Free |
|---------|------|
| Feed / Pump / Diaper / Sleep logging | Unlimited |
| **Caregiver share (editor permission)** | Unlimited caregivers |
| Multi-baby | 1 baby |
| History | Last 90 days |
| Freezer stash | 20 bottles |
| Vaccination log | Unlimited |
| Daily summary | Basic |
| Ads | None (matches DreamBaby philosophy) |

### 7.2 Premium tier

| Feature | Premium |
|---------|---------|
| Multi-baby | Unlimited |
| History | Lifetime + **CSV export** |
| Freezer stash | Unlimited + expiry alerts |
| **Visit Summary PDF** | ✅ |
| Weekly/Monthly charts + insights | ✅ |
| AI pattern insights | ✅ (v1.1) |
| DreamBaby Bedtime Routine integration | ✅ (v1.2) |
| Caregiver permission levels (read-only / admin) | ✅ |
| Custom feeding types + tags | ✅ |

### 7.3 Pricing (matches DreamBaby — both apps repriced 2026-05-13)

```
Monthly  $2.99 / 99฿
Yearly   $19.99 / 599฿  ⭐ Most popular (Save 58%)
Lifetime $29.99 / 899฿
Trial    7 days (subscriptions only)  [D4]
```

**DreamBaby also raised to same tiers** (pre-launch, zero migration friction).

**Lifetime safety guarantee:** Both apps must never ship a per-user variable-cost feature (custom AI generation, cloud rendering, LLM-per-query). Content is library-based (pre-generated, stored in R2, shared by all users) so lifetime cost is bounded by production budget, not user count. See companion content strategy in DreamBaby memory.

**Bundle (RevenueCat offering):** "Niyoko Baby Bundle Lifetime" = DreamBaby + DreamBook lifetime → **$44.99** (save $15 vs $59.98 separate).

### 7.4 Future bundle

RevenueCat offering: **"Niyoko Baby Bundle"** = DreamBaby + DreamBook lifetime → ~$34.99 (save $5) — set up after both apps prove individual revenue.

---

## 8. Branding

- **Name:** DreamBook
- **Thai:** ดรีมบุ๊ค / สมุดบันทึกลูกน้อย
- **Publisher:** Niyoko Studio
- **Tagline (EN):** "Every drop, every dream — recorded with care."
- **Tagline (TH):** "ทุกหยดน้ำนม ทุกชั่วโมงนอน — บันทึกด้วยความใส่ใจ"
- **Visual identity:** Inherit DreamBaby's calm-pastel palette + soft-rounded type. Replace audio-wave motif with **notebook + droplet motif**. Family DNA preserved; distinct silhouette.
- **Mascot:** **"Dreamer Bunny"** — soft lavender bunny holding a tiny notebook; appears in empty states, premium upsell, app-icon corner, and DreamBaby cross-promo. Commission alongside empty-state illustrations. [D8]
- **App icon:** Outsourced illustrator (~$200) — mascot variant (Dreamer Bunny + notebook). [D12]
- **Store listing:** TH freelance copywriter (~$100) for native-feeling TH long description and ASO keywords. [D10]

---

## 9. Privacy & Security

1. **No login required** — device ID + optional invite code only
2. **All local data encrypted** at rest via `sqflite_sqlcipher`
3. **All synced data encrypted client-side** — Supabase sees only ciphertext + row metadata
4. **Family key never sent in plaintext** — only invite-code-wrapped during onboarding handshake
5. **No analytics SDK** by default — Crashlytics is opt-in (mirror DreamBaby)
6. **Photo storage (v1.1):** local-only by default; optional encrypted-relay for share at premium tier
7. **Right-to-be-forgotten:** "Delete my data" wipes local DB + sends tombstones for all owned rows to Supabase

---

## 10. Notifications policy

- **Inexact only.** Never use `alarmClock`, `setExactAndAllowWhileIdle`, or any exact-alarm permission (Android 14+ crash risk + Play Store rejection — per DreamBaby memory).
- Use cases: stash expiry, pump reminders (user-configured), feed reminders if mom enabled.
- All reminders are user-opt-in. Default = off.

---

## 11. Localization

- **v1.0:** English (USA) + Thai (Thailand)
- **v1.1+:** Spanish, Portuguese-BR, Japanese, Korean, German (mirror DreamBaby expansion plan)
- ARB files in `/lib/l10n` via `flutter_localizations` + `intl`

---

## 12. Out of Scope (v1.0)

| Item | Why deferred | When |
|------|-------------|------|
| Solids / food diary | Target user = 0–6mo baby, no solids yet | v1.1 |
| Growth chart + WHO percentile | Charting work, can wait | v1.1 |
| Milestone tracker | Nice-to-have | v1.1 |
| Med tracker | Niche; vaccination covers most needs | v1.1 |
| Photo per entry | Storage + cross-device privacy = thorny | v1.1 |
| AI insights | Need data first | v1.1 |
| Vaccination schedule (auto) | Liability per-country | Maybe never |
| Doctor appointment calendar | Google Calendar exists | Out |
| Apple Watch / Wear OS | Volume too small | v1.3+ |
| Web dashboard | Mobile-first | v1.3+ |
| iCloud sync option | Android-first launch makes it dead weight | Maybe v1.2 |

---

## 13. Risks & Open Questions

| Risk | Mitigation |
|------|-----------|
| Supabase free tier overrun on success | Move to paid ($25/mo for 100k MAU); revenue from premium covers it many times over |
| Sync conflicts on bursty caregiver writes | Last-write-wins + per-table version → loss only happens on millisecond races, acceptable for non-critical baby logs |
| Caregiver enters wrong invite code | 1-hour TTL + 6-digit space (~10M combos) + rate-limit per device |
| Mom uninstalls and loses family key | Premium feature v1.1: "Backup recovery phrase" (12-word BIP-39-style) — opt-in |
| DreamBaby release slip delays v1.2 | v1.0/v1.1 are independent; only v1.2 needs DreamBaby data contract |
| Thai market doesn't pay | USA is primary; TH is bonus organic traffic |
| Pediatricians won't accept PDF report | Generate as both PDF (visual) + plain print-friendly HTML; iterate after launch |

**Open questions to resolve before implementation plan:**
1. Should the invite code be 6 digits or 8? (UX vs entropy trade-off — 6 ≈ 10M combos is fine with rate-limiting)
2. Do we want a "Recently active caregivers" indicator on Home? (privacy implication if shown without consent)
3. Pump reminders default on/off? (acquisition vs creepy)

---

## 14. Success Metrics

### Acquisition (first 90 days post-launch)
- 5,000 installs (Android-only baseline; DreamBaby comp)
- 35% D1 retention
- 15% D7 retention

### Engagement
- Median 4 log entries / user / day
- 25% of accounts have ≥1 caregiver invited (validates differentiator hypothesis)

### Revenue
- 2.5% free → paid conversion (matches DreamBaby plan)
- $0.85 ARPU month 3

### Quality
- Crash-free rate ≥ 99.5%
- App Store rating ≥ 4.5 (Play Store), ≥ 4.6 (App Store later)

---

## 15. Timeline (rough estimate)

| Week | Milestone |
|------|-----------|
| 1 | Flutter project init, DB schema, encrypted sqflite, basic routes |
| 2 | Feed + Bottle UI + log → DB |
| 3 | Pump session + Stash inventory + expiry alerts |
| 4 | Diaper + Sleep logging |
| 5 | Daily summary + history view + 90-day cap enforcement |
| 6 | Supabase project setup, sync worker, E2E encryption |
| 7 | Invite code flow + caregiver onboarding |
| 8 | Multi-baby + premium gating via RevenueCat |
| 9 | Vaccination log + Visit Summary PDF |
| 10 | DreamBaby deep-link (light bridge) + L10n EN+TH polish |
| 11 | QA, beta, Play Store internal track |

**Buffer:** 1 week for incidents.

---

## 16. Definition of Done (v1.0)

- All Must-have features in §5 working on Android emulator + physical device
- Caregiver share end-to-end tested with 3 simulated devices
- E2E encryption verified (Supabase row contents are ciphertext via SQL inspection)
- Crash-free rate ≥ 99% in beta
- EN + TH both reviewed by native readers
- Play Store internal track passes review
- DreamBaby deep-link tested (with DreamBaby installed and not installed)
- Visit Summary PDF generated and rendered correctly on iOS Mail / Gmail / Thai SMS forward

---

## 17. UX/UI Design (senior UX/UI input)

### 17.1 Core principles

1. **One-thumb operation** — mom holds baby with one arm; primary actions live in the lower two-thirds of every screen.
2. **Auto night-mode 20:00–06:00** — dark theme switches automatically; an optional **red-tint mode** is available (preserves melatonin during night-feeds).
3. **Smart defaults** — remember last feed side, last oz, last duration → tap-tap-save in <5 seconds.
4. **Logging beats insights** — make the log path fast; analytics can wait until users want them.
5. **Caregiver attribution everywhere** — every entry shows who logged it (avatar pill + name + relative time).
6. **Warm empty states** — first-launch, no-entries-today screens use soft illustrations, never corporate blanks.
7. **Cross-platform native feel** — Material 3 on Android, iOS HIG on iOS via Flutter's adaptive widgets; never look like a port.

### 17.2 Key screens

#### Home (most-used, designed for repeat 8–12× per day)
- **Top bar:** Baby switcher chip + age in weeks/months (e.g., "Mali · 8 weeks") + invite caregiver shortcut
- **Hero card:** Today's summary, 4 stats (oz fed / # diapers / sleep hrs / # pumps)
- **Quick-Log grid:** 2×2 large tappable buttons (Feed / Pump / Diaper / Sleep) bottom-half, thumb-reachable
- **Activity feed:** Recent entries scrolling, each row shows caregiver avatar + name + type + time
- **FAB bottom-right:** "+ New entry" catch-all

#### Pump session (the killer screen for pumping moms)
- L/R split card with two large tappable halves
- Center: live timer counting up
- **End session** → number-pad modal: separate L oz / R oz entry, smart-defaulted from last session
- **Save to stash** toggle (default ON) + 1-tap bottle-count preview
- Microhaptic on save; never modal-blocks the screen

#### Invite caregiver (the magic moment — sub-30-second handoff)
- Modal sheet: "Invite to help log Baby Mali"
- **6-digit code displayed huge** (40+ pt font, tabular numerals, monospaced) center stage
- **QR code** beneath as faster alternative
- Native share sheet button: "Share via..." (auto-prefills WhatsApp/LINE/SMS message)
- Countdown chip: "Expires in 0:58:42"
- Below: previously-invited caregivers list with online/offline status

#### Caregiver onboarding (3 screens max)
1. "I have a code" → enter 6-digit code or scan QR
2. "Connecting securely…" with lock icon (real time, build trust during ~2-sec key exchange)
3. "✨ Connected to Baby Mali — tap to start logging"

#### Daily / Weekly Summary (pediatrician-friendly)
- Date picker top (with 90-day cap for free, lifetime for premium)
- 4-tile dashboard
- Tap any tile → drill-down chart
- **"Generate Pre-visit PDF"** button (premium-gated, paywall on tap if free)

#### Freezer Stash (visual differentiator)
- Bottle icons in a grid, color-coded by age:
  - 🟢 Green = fresh (< 1 month)
  - 🟡 Yellow = aging (1–4 months)
  - 🔴 Red = near-expiry (< 1 month to expires_at)
- Tap bottle → details + "consume / discard" actions
- FIFO suggestion banner: "Use the green-marked bottles first"

### 17.3 Anti-patterns to avoid

| ❌ Anti-pattern | ✅ Instead |
|----------------|-----------|
| Onboarding wall (Huckleberry: 10 questions before letting you in) | 1 screen — baby name only required, rest skippable |
| Banner / interstitial ads (Glow Baby pattern) | Zero ads ever — premium upsell only at high-intent moments |
| Modal popups for non-critical info | Bottom sheets, dismissible by swipe-down |
| Generic Material 3 defaults | Custom calm pastel + soft rounded type, branded micro-details |
| Long forms for routine logs | Max 2 taps + 1 number input per common log |
| Buried logout / data export | "Delete my data" prominent in Settings (privacy positioning) |

### 17.4 Microinteractions

- Soft haptic feedback on log save (`HapticFeedback.lightImpact`)
- Optional gentle "pop" sound (default **off** — night-feed safe)
- Number inputs always offer +/− steppers in addition to keyboard (greasy-finger friendly)
- Pull-to-refresh on Home triggers sync + shows "Synced X seconds ago"
- Confetti on first milestone (v1.1)

### 17.5 Accessibility (a11y)

- Minimum body text 16 pt; scales with system Dynamic Type / Android font scale
- Contrast ratio ≥ 4.5:1 for body, ≥ 3:1 for large text
- VoiceOver / TalkBack labels for all interactive elements (including Quick-Log buttons)
- Never color-only meaning: use icon + label together
- Caregiver avatar = letter-initials fallback when no photo (no anonymous gray ghosts)

### 17.6 Typography

| Use | Font | Reason |
|-----|------|--------|
| EN body | SF Pro (iOS) / Roboto (Android) — system | Native feel, Dynamic Type support |
| TH body | **IBM Plex Sans Thai** or **Sarabun** | Correct vowel/tone-mark positioning (display fonts often break this) |
| Numerals | **Tabular** variant | Stat columns align under each other |
| Headings | Weight 600, slightly tightened tracking | Soft modern, not corporate |

### 17.7 Color palette (inherit DreamBaby + add)

| Token | Light | Dark | Night-tint |
|-------|-------|------|-----------|
| Primary | `#B7A7DD` (soft lavender) | `#9080C0` | `#7060A0` |
| Accent | `#F4C2A0` (warm peach) | `#D9A684` | `#A06040` |
| Success | `#90B89A` (sage) | `#7AA084` | `#608070` |
| Warning | `#E8B547` (honey) | `#C99A35` | `#996020` |
| Surface | `#FFF8F0` (cream) | `#1A1F2E` (deep navy) | `#2A1010` (warm red-tint) |
| On-surface | `#2D2A35` | `#E8E2F0` | `#E0C8B8` |

### 17.8 Iconography

- Custom **24×24 stroke icons** (2 px stroke, rounded caps) — bottle, droplet, moon, diaper, scale, syringe
- Never use Material defaults for primary actions — feels generic
- Use Lucide/Tabler as base, customize for baby metaphors (bottle, pump, droplet)

### 17.9 Screen inventory (v1.0)

| Route | Screen | Premium-gated? |
|-------|--------|---------------|
| `/onboarding` | First-launch baby profile | – |
| `/home` | Daily logging dashboard | – |
| `/feed/new` | New feed entry | – |
| `/pump/new` | Pump session | – |
| `/diaper/new` | New diaper entry | – |
| `/sleep/new` | New sleep entry | – |
| `/stash` | Freezer stash inventory | – (cap-gated free) |
| `/summary` | Daily/weekly summary | – (90-day cap free) |
| `/summary/pdf` | Visit Summary PDF preview | ✅ |
| `/vaccination` | Vaccination log | – |
| `/share` | Caregiver invite + list | – |
| `/share/join` | Caregiver onboarding | – |
| `/babies` | Multi-baby switcher | – (1-baby cap free) |
| `/settings` | Settings + premium upsell | – |
| `/settings/premium` | Paywall + RevenueCat | – |

---

## 18. Senior Cross-Functional Review (added 2026-05-13)

Each senior gives: **red flag**, **what they'd change**, **open question**.

### 18.1 🏗️ Senior Backend / DevOps Architect

- **Red flag:** Supabase RLS for E2E encrypted rows is subtle — anyone with `family_id` could write *any* ciphertext row by design; we need write/update/delete restricted to authenticated caregiver devices of that family.
- **Change:** Add `family_caregivers (family_id, device_id, role, joined_at, revoked_at)` table; RLS policy: `family_id` matches AND `device_id == auth.uid()` AND `revoked_at IS NULL`.
- **Add:** Cloudflare in front of Supabase REST endpoint for rate-limiting (free tier covers 100k req/day) — defense against invite-code brute force.
- **Open Q:** Pick Supabase region — `ap-southeast-1` (Singapore) for TH latency, or `us-east-1` for USA latency? Mixed user base — recommend **Singapore** (TH latency win > USA latency loss).

### 18.2 🔐 Senior Security / Privacy Engineer

- **Red flag:** 6-digit invite code = ~1M combos. With rate-limit OK, but recommend upgrading to **8-char Crockford base32** (no `0/O`, `1/I`, ambiguous) → ~10^11 space, still readable (e.g., `MK2-9HFX4`).
- **Change:** Section §9 add formal **threat model**:
  - T1: Lost mom phone → caregivers' copies keep working; ship "Revoke all access" → rotates family key, re-distributes via existing online caregivers
  - T2: Hostile caregiver → "Revoke caregiver" button; old data they synced before revoke stays on their phone (accepted) but no new writes
  - T3: Supabase compromise → adversary sees ciphertext + metadata only; cannot decrypt without family key
  - T4: MITM on invite handshake → invite code's TTL is 1h AND single-use AND fingerprint pinned to first claiming device
- **Change:** Store family key in **Keychain (iOS)** / **EncryptedSharedPreferences (Android)** via `flutter_secure_storage`, NOT in sqflite (sqflite is also encrypted but Keychain has hardware-backed protection on most devices).
- **Add:** Data Processing Agreement template since data crosses borders (TH user data sits in Singapore Supabase region).
- **Open Q:** Recovery — if mom loses phone and family key, all encrypted data on Supabase becomes garbage. Offer optional **12-word BIP-39 recovery phrase** as premium feature? (Adds support burden but prevents catastrophic data loss complaints.)

### 18.3 📱 Senior Mobile / Flutter Engineer

- **Red flag:** **iOS background sync is severely limited.** `BGTaskScheduler` wakes are ~2-3 min, frequently denied by iOS. Cannot promise "Mom logs → Dad sees in 30 sec" while Dad's app is backgrounded.
- **Change:** Use **Supabase Realtime (websocket)** for active sync when both phones are foregrounded — much faster than polling. Background = best-effort only; mark explicitly in UX.
- **Change:** Add "Last synced X ago" timestamp pill on Home → manages user expectations.
- **Red flag:** `sqflite_sqlcipher` had Bitcode/iOS build flake last year — pin specific version + test on iOS clean build week 1.
- **Add:** Both Android and iOS — never request `SCHEDULE_EXACT_ALARM` (per DreamBaby memory rule); inexact alarms only.
- **Add:** Use Flutter's `adaptive` widgets (`CupertinoAdaptive*` patterns) so iOS feels native; do NOT ship Material 3 on iOS.
- **Open Q:** Do we ship **iOS App Clip** (a small subset of the app for caregiver QR-scan onboarding without full install)? Slick but extra work. Probably skip v1.0.

### 18.4 🧪 Senior QA / Test Lead

- **Red flag:** Sync conflict logic is highest bug-risk in the whole app. Cannot test with manual QA alone.
- **Add:** Build a **sync simulator** (week 6) — Dart test harness that boots N virtual devices, runs scripted timelines (offline writes, reconnects, revokes) and asserts final state matches across all.
- **Add:** Required scenarios:
  - 2 phones offline, both log same Feed entry → must reconcile (last-write wins, no duplicate)
  - 1 phone offline, 2 online phones make 10 writes → offline phone must catch up correctly on reconnect
  - Mom revokes Caregiver A while A is offline → A's reconnect must reject new writes from A
  - Mom rotates family key → old caregivers must re-handshake or be locked out
- **Add:** Beta plan — TestFlight + Play Console internal week 8, **closed family beta (5–10 real families)** week 10, public soft-launch week 11.
- **Open Q:** Acceptable test coverage threshold for v1.0 — recommend **80% line, 100% branch on `core/sync` + `core/crypto`**.

### 18.5 ⚖️ Senior Legal / Compliance

- **Red flag:** App handles **personal data of minors (under 13)** — falls under **COPPA (USA)**, **GDPR-K (EU)**, **PDPA (TH)**. Stricter than adult-data apps.
- **Add:** Privacy Policy MUST state:
  - No 3rd-party analytics SDK
  - Exact data location (Supabase Singapore region)
  - Caregiver share = consent transfer (mom is data controller, invites grandparent as joint controller)
  - Right-to-deletion within 30 days (matches GDPR/PDPA)
- **Add:** Terms of Service clause: *"DreamBook is NOT a medical device. The Pre-visit Report is for informational purposes only. Always consult a licensed pediatrician for medical decisions."*
- **Add:** Crashlytics opt-in must be EXPLICIT (toggle in onboarding, default OFF). Same for crash logs that might contain entry notes.
- **Action:** Get a kids-data privacy lawyer to review final PP + ToS before public launch — non-negotiable.
- **Open Q:** Should we explicitly target only 0–24 month babies (clinically distinct from older kids) to avoid scope creep + reduce COPPA exposure for kids near 13? Recommend yes — Marketing positions DreamBook as "newborn-to-toddler".

### 18.6 👩‍⚕️ Senior Pediatric Clinical Advisor

- **Red flag:** Visit Summary PDF currently shows last 14 days — pediatricians look at **last 7 days** for newborn checkup conversations.
- **Change:** Default PDF range = **7 days** (with toggle for 14/30 days).
- **Add to PDF essential fields:**
  - Daily wet diaper count + soiled diaper count (key indicator of adequate feeding in newborns)
  - Total intake oz/day (chart)
  - Longest sleep stretch per day (sleep regression assessment)
  - Vaccination history with last-dose dates
  - "Concerns to discuss" optional free-text field (parents fill in pre-visit)
- **Add:** Disclaimers in PDF footer: *"This report is parent-recorded and not a substitute for medical examination."*
- **Recommend:** Pediatrician test panel — 3 pediatricians (2 USA, 1 TH) review PDF before public launch. Pay $50 each via test gift card.
- **Open Q:** Should DreamBook surface **AAP feeding norms** (e.g., "8-week-olds typically take 24-32 oz/day") inline? Useful but verging on medical advice — recommend **no** for v1.0, revisit with legal in v1.1.

### 18.7 🔍 Senior ASO Specialist

- **Red flag:** "DreamBook" is short and brandable but loses Play Store keyword search (people search "baby tracker", "pumping app", "feeding log").
- **Change:** Store listing structure (matches HuayCheck pattern from memory):
  - **App name:** `DreamBook` (35 chars limit on Android)
  - **Subtitle / short desc:** `Baby Daybook & Pump Tracker` (30 chars iOS, 80 chars Android short)
  - **TH short desc:** `สมุดบันทึกลูกน้อย ปั๊มนม กินนอน` 
  - **Long desc:** lead with "no-login share" differentiator within first 2 sentences (Google indexes only first 500 chars)
- **Add:** 8-screen Play Store storyboard:
  1. Hero: "Track every drop. Share with your family." + Home screen
  2. Pump session screen + freezer stash visual
  3. Caregiver share invite flow (6-digit code)
  4. Daily summary stats
  5. Visit Summary PDF preview
  6. Privacy-first (lock icon + "no account, no cloud")
  7. Multi-baby + vaccination log
  8. DreamBaby companion tease
- **Add:** Featured graphic shows the **6-digit invite code** prominently — that's the marketing wedge.
- **Open Q:** App icon — hire freelance illustrator for distinctive icon (~$200 on Dribbble/99designs), or DIY in Figma? Recommend hire; ASO testing shows icon ↑ install rate by 15-30%.

### 18.8 🌏 Senior Localization / TH Market Specialist

- **Red flag:** Thai grandmas (ย่า/ยาย) often don't use smartphones — primary caregiver-share use case in TH is mom ↔ dad ↔ nanny, NOT mom ↔ grandma. **TH adoption of share feature will be 30-40% lower than USA.**
- **Change:** Onboarding copy should hint at common cases: "Invite your partner, nanny, or daycare" — not just "family".
- **Add:** Thai-specific nice-to-have for v1.1:
  - Show both **lunar calendar age** (จันทรคติ) + western age — many Thai parents track both
  - Pre-loaded milestone preset: **first-month ceremony (ทำขวัญเดือน)** at 1 month
  - Nickname field (ชื่อเล่น) prominent + full Thai name optional — most daily logging uses nickname
- **Add:** SMS fallback for non-app caregivers — premium feature, send daily summary as SMS link to grandma's phone (uses Twilio or similar; small cost). v1.1+.
- **Open Q:** TH App Store / Play Store screenshots — use real Thai names ("น้องมะลิ") and nicknames in mocks. Approve hiring a TH freelance copywriter for store listing (~$100)?

### 18.9 💰 Senior Pricing / Unit Economics Analyst

- **Red flag:** 3-night trial works for DreamBaby (parents feel value night 1) but is **too short for a daybook** — value emerges from 1-2 weeks of accumulated logs.
- **Change:** **7-day free trial** for DreamBook subscriptions (RevenueCat A/B test 3 vs 7 if curious post-launch).
- **Add unit economics check:**
  - Yearly avg ARPU @ $14.99/yr ≈ $1.25/mo
  - Target conversion 2.5% → blended ARPU $0.03/user — Supabase free tier covers up to ~50k MAU comfortably
  - At 50k MAU and 2.5% conversion = 1,250 paying × $1.25 = **$1,562/mo** → covers Supabase paid upgrade + dev support easily
  - LTV breakeven: 8 paying users → trivial
- **Add:** Track these metrics in RevenueCat from day 1:
  - Free-to-trial conversion
  - Trial-to-paid conversion
  - Paid retention M1 / M3 / M12
  - Lifetime purchase ratio (lifetime vs yearly)
- **Open Q:** Test **$24.99 Lifetime** in USA store from week 11 launch? (DreamBaby is $19.99 — DreamBook arguably has more value because of share feature). Recommend yes, A/B via RevenueCat experiments after first 1k users.

### 18.10 🎨 Senior Brand / Illustrator

- **Red flag:** DreamBook needs a distinct identity from DreamBaby — but share family DNA (same studio).
- **Add:** Visual identity guide:
  - DreamBaby motif: **moon + soundwave** (audio focus)
  - DreamBook motif: **notebook + droplet** (logging + milk focus)
  - Shared: lavender + peach palette, soft rounded type, hand-drawn warmth
- **Add:** 5 hand-drawn empty-state illustrations (commission ~$150 total on Dribbble):
  - Baby bottle (empty Feed list)
  - Sleeping baby (empty Sleep list)
  - Diaper stack with question mark (empty Diaper list)
  - Pump + droplet (empty Pump list)
  - Two hands passing notebook (empty Caregivers list)
- **Add:** App icon options to test:
  - A) Notebook silhouette with lavender bookmark
  - B) Droplet inside a circle (more abstract)
  - C) Tiny bunny mascot holding a notebook (cute, more memorable)
- **Open Q:** Do we want a **mascot character** ("Dreamer Bunny"?) — easier ASO, more memorable, but more illustration work. Recommend yes if budget allows.

---

## 19. Decisions emerging from senior review — ✅ LOCKED 2026-05-13

| # | Decision | Locked | Inlined? |
|---|----------|--------|---------|
| D1 | Invite code = 8-char Crockford base32 (`MK2-9HFX4`) | ✅ | §5.7 |
| D2 | Family key in `flutter_secure_storage` (Keychain / EncryptedSharedPreferences) | ✅ | §6.1 |
| D3 | Supabase region = `ap-southeast-1` Singapore | ✅ | §6.1 |
| D4 | Trial = 7 days | ✅ | §7.3 |
| D5 | Visit PDF default = 7 days + wet/soiled diaper + longest sleep stretch | ✅ | §5.9 |
| D6 | 12-word BIP-39 recovery phrase as premium opt-in | ✅ | §13 (v1.1) |
| D7 | Sync simulator built week 6 (Dart test harness) | ✅ | §15, §18.4 |
| D8 | Mascot "Dreamer Bunny" + empty-state illustrations | ✅ | §8 |
| D9 | Pediatrician test panel (3 pediatricians, $150 total) | ✅ | §18.6 |
| D10 | TH freelance copywriter for store listing ($100) | ✅ | §8 |
| D11 | Pricing: $2.99/$19.99/$29.99 for both apps; bundle $44.99 lifetime; no per-user variable-cost features allowed (lifetime safety) | ✅ | §7.3 |
| D12 | App icon outsourced illustrator (~$200) | ✅ | §8 |
| D13 | Target age = 0–24 months (COPPA exposure reduction) | ✅ | §2.1 |
| D14 | Kids-data privacy lawyer reviews PP+ToS before public launch | ✅ | §18.5 |
| D15 | iOS App Clip = skip v1.0; revisit v1.2 | ✅ | §18.3 |

**Estimated pre-launch external spend:** ~$450–650 (illustrator + 3 pediatricians + TH copywriter + lawyer retainer)

---

## 20. Next steps (post-spec approval)

1. User reviews spec + confirms/adjusts §19 decisions D1–D15
2. Apply final decisions into spec body (replace §5/§6/§7/§17 references)
3. (Later, when ready to build) Invoke `writing-plans` skill to break v1.0 into an implementation plan with task graph
4. (Even later) Implementation via `subagent-driven-development` or async via `executing-plans`
5. **Visual mockups** of the 5 critical screens (Home / Pump / Invite / Caregiver Onboarding / Visit PDF) generated via brainstorming Visual Companion when user is ready to evaluate UX visually
6. DreamBook is a **standalone Flutter project** at `/Users/nipitphand/Projects/DreamBook` (scaffolded 2026-05-13)

---

*End of spec. Companion to DreamBaby at `/Users/nipitphand/Projects/DreamBaby`.*
