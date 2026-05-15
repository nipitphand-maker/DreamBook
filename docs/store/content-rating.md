# DreamBook — Google Play Content Rating Questionnaire

Reference: Google Play content rating system (IARC)
App: DreamBook — Baby Daybook
Developer: Niyoko Studio
Date: 2026-05-15

---

## 1. App Category

**Primary category:** Health & Fitness / Parenting
**Target audience:** Adults (parents and caregivers of babies aged 0–24 months)
**The app itself is NOT intended for use by children.** It is a tool used BY parents/caregivers to track infant health data.

---

## 2. Violence

| Question | Answer |
|---|---|
| Does the app contain depictions of violence? | No |
| Does the app contain cartoon or fantasy violence? | No |
| Does the app reference violence in any form? | No |

---

## 3. Sexual Content

| Question | Answer |
|---|---|
| Does the app contain sexual content or nudity? | No |
| Does the app contain suggestive or mature themes? | No |
| Does the app reference or link to sexual content? | No |

---

## 4. Language / Profanity

| Question | Answer |
|---|---|
| Does the app contain profanity or strong language? | No |
| Does the app allow users to submit text that others can see? | No — caregiver notes are private and never shared publicly |

---

## 5. Controlled Substances

| Question | Answer |
|---|---|
| Does the app reference alcohol, tobacco, or drugs? | No |
| Does the app promote or facilitate purchase of controlled substances? | No |

---

## 6. User-Generated Content (UGC)

| Question | Answer |
|---|---|
| Does the app allow users to generate content visible to others? | No |
| Does the app have a public social feed? | No |
| Does the app have public user profiles? | No |
| Does the app allow public messaging? | No |
| Does the app have any form of UGC moderation challenges? | No |

**Notes on caregiver sharing:**
The app's caregiver-sharing feature uses an 8-character invite code. Shared data is:
- Visible ONLY to explicitly invited family members/caregivers
- End-to-end encrypted in transit and at rest
- Not publicly discoverable
- Not a social network feature

This is equivalent to a private family sync, not user-generated public content.

---

## 7. Data Collection & Privacy

| Data type collected | Purpose | Stored where | Shared with third parties? |
|---|---|---|---|
| Baby feeding logs (times, volumes) | Core app functionality | On-device (encrypted) | No |
| Diaper logs | Core app functionality | On-device (encrypted) | No |
| Sleep logs | Core app functionality | On-device (encrypted) | No |
| Vaccination records | Core app functionality | On-device (encrypted) | No |
| Pump session data | Core app functionality | On-device (encrypted) | No |
| Freezer stash data | Core app functionality | On-device (encrypted) | No |
| Cloud backup (premium, opt-in) | User-controlled backup | Encrypted cloud storage | No |
| Crash reports (opt-in only) | App stability | Sentry (opt-in) | Only if user consents |

**No advertising SDK is included.**
**No analytics SDK is included.**
**No third-party data brokers receive any data.**

---

## 8. COPPA (Children's Online Privacy Protection Act)

| Question | Answer |
|---|---|
| Is the app directed at children under 13? | No |
| Do users of the app include children under 13? | No — the app is used by parents and caregivers (adults) |
| Does the app collect personal information from children under 13? | No |

**Clarification:** DreamBook tracks data ABOUT infants (0–24 months) but is operated exclusively BY adults (parents, caregivers). The infants are not users of the app; their data is entered by an adult on their behalf. This is analogous to a parent using a health journal for their child.

---

## 9. Sensitive Permissions

| Permission | Required? | Reason |
|---|---|---|
| INTERNET | Yes | Premium cloud backup sync (opt-in, encrypted) |
| CAMERA | No | Not requested |
| MICROPHONE | No | Not requested |
| LOCATION | No | Not requested |
| CONTACTS | No | Not requested |
| READ_EXTERNAL_STORAGE | No | Not requested |
| WRITE_EXTERNAL_STORAGE | No | Not requested (PDF export uses system share sheet) |

---

## 10. Advertising

| Question | Answer |
|---|---|
| Does the app show ads? | No |
| Does the app use an advertising SDK? | No |
| Does the app show interest-based or behaviorally targeted ads? | No |

---

## 11. Recommended Content Rating

Based on the above answers, the expected IARC rating is:

**ESRB: E (Everyone)**
**PEGI: 3**
**USK: 0**
**ClassInd: L (Livre)**

These ratings reflect a clean, family-friendly health utility with no mature content, no violence, no UGC, and no advertising.

---

## 12. Google Play Target Age Group Declaration

**Target age group:** 18 and over (adults)
**Reason:** The app is a health tracking tool designed for parents and caregivers. It is not designed for use by children. The data tracked concerns infants, but the users of the app are adults.
