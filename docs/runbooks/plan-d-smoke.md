# Plan D — Manual smoke checklist (Premium, Multi-baby, Gating)

Pre-req: debug APK installed on an Android emulator (or real device) signed in to a Google Play account that can see the RevenueCat-linked sandbox products. RevenueCat dashboard configured with the `premium` entitlement and three packages (`monthly`, `yearly`, `lifetime`). `.env` includes a valid `REVENUECAT_API_KEY` (Android public SDK key).

> Conventions: "free user" = entitlement `premium` NOT active. "paid user" = entitlement `premium` active. To toggle quickly, use RevenueCat dashboard → Customers → grant/revoke `premium` entitlement, then cold-relaunch the app (forces `Purchases.getCustomerInfo()` to refetch).

---

## 1. Paywall — RevenueCat integration

- Cold-launch app as free user; from Home → settings cog → tap **Get Premium** tile.
- **PASS**: Paywall route `/settings/premium` opens with three package cards: **Monthly $2.99**, **Yearly $19.99**, **Lifetime $29.99**.
- **PASS**: **Yearly** is pre-selected (highlighted border / radio checked) and shows the "Save XX%" badge.
- Tap each package — radio state updates without jank.
- Tap **Restore purchases** with no prior purchases on the test account.
  - **PASS**: No crash. A toast / SnackBar surfaces "No purchases to restore" (or equivalent). Paywall stays open.
- Tap **Continue** / **Subscribe** on Yearly → Google Play sandbox sheet appears.
  - Dismiss without buying → returns to paywall without crash.
- (Optional: dry-run real sandbox purchase) Complete a sandbox purchase → paywall closes → Home shows premium-only widgets unlocked.

## 2. Multi-baby — Baby switcher

- As free user with **one** existing baby logged in, from Home tap the baby chip / avatar (or settings → Babies) → `/babies` opens.
- **PASS**: Switcher lists the existing baby with a checkmark / "active" indicator next to it.
- Tap the existing baby → no-op (already active), screen does not crash.
- Tap **Add baby** FAB (or `+` in the AppBar).
  - As **free user**: app navigates to `/settings/premium` (paywall), does NOT open the Add-baby form.
  - **PASS**: paywall route opened; no exception in `flutter logs`.
- (Set entitlement to active in RC dashboard, cold relaunch.) Re-tap **Add baby**.
  - **PASS**: `add_baby_screen` opens. Fill name, dob, sex, preferredUnit; tap **Save**.
  - **PASS**: Switcher now shows two babies. New baby is selected as current.
- Tap the previous baby → it becomes current; Home stats reflect the switch (feed/pump/diaper/sleep totals change).

## 3. Stash — Free-tier cap gating

- As free user, navigate to `/stash`.
- Add bottles via the `+` AppBar action until the active count reaches **20**.
- Tap the FAB / `+` for the 21st time.
  - **PASS**: app navigates to `/settings/premium`. The Add-bottle sheet does NOT open.
  - **PASS**: No crash. Existing 20 bottles remain visible & FIFO-ordered.
- Consume or discard one bottle (count drops to 19).
- Tap `+` again.
  - **PASS**: Add-bottle sheet opens (because count < 20).
- Switch to paid user (RC dashboard grant + cold relaunch).
- Add bottles 21, 22, 23 → no gating; sheet opens each time.

## 4. Summary — PDF export lock

- As free user, open `/summary` (Daily Summary).
- Scroll to the **Export PDF** / **Visit Summary PDF** action.
  - **PASS**: button shows lock icon (or PremiumGate's default chip).
  - Tapping it routes to `/settings/premium`, does NOT trigger PDF generation.
- Switch to paid user → cold relaunch → re-open summary.
  - **PASS**: lock icon is gone; tap triggers PDF preview / share sheet (Plan E surface).

## 5. Settings — Premium tile state

- As free user, open `/settings`.
  - **PASS**: tile reads **Get Premium** with a CTA chevron; tap routes to `/settings/premium`.
- As paid user (cold relaunch).
  - **PASS**: tile reads **Premium · Active** (or equivalent localized text). Tap opens RevenueCat customer center / manage-subscription link, does NOT route to the paywall purchase flow.

## 6. PremiumGate — Failure modes

- Airplane mode ON, cold-launch app as a previously-paid user (RC cached entitlement should persist offline).
  - **PASS**: paid features still unlocked from cache; no crash.
- Airplane mode ON, cold-launch as a free user.
  - **PASS**: free features work; locked features show the lock chip; tapping it opens the paywall route (which itself will show an error/retry banner if RC can't fetch offerings — that's the Lead team's concern, not PremiumGate's).
- Force RC error (e.g., revoke API key in `.env`, hot-restart).
  - **PASS**: locked features stay LOCKED (fail-closed). No silent grant of premium.

## 7. L10n

- Toggle device language to Thai → re-open paywall.
  - **PASS**: package titles, restore button, settings tiles, and gate chips render Thai strings (or English fallback if not yet localized — file a follow-up rather than fail).

---

## Known false-positives

- First cold launch after RC SDK init may show a 0.5-1s flicker where gated features appear unlocked. This is intentional — PremiumGate returns the unlocked child during the AsyncValue `loading` state to avoid a chip-then-flash on every screen. Acceptable; not a bug.
- RevenueCat sandbox accounts on Google Play can take 1-2 minutes to propagate entitlement changes. Always cold-relaunch after toggling in the RC dashboard.
