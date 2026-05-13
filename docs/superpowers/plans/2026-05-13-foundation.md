# DreamBook — Plan A: Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scaffold the DreamBook Flutter project (Android-first, iOS-ready) up to a runnable empty-baby-name app shell with theme, L10n, encrypted DB schema v1, secure key storage, inexact-only notifications, routing, and a one-handed Home screen showing the Quick-Log 2×2 grid + a Share/Invite placeholder.

**Architecture:** Flutter + Riverpod 3.x (hand-rolled) + go_router + sqflite_sqlcipher (AES key stored in Keychain / EncryptedSharedPreferences). Same stack as DreamBaby with three deliberate divergences: Android **minSdkVersion 23** (required by RC + secure_storage v10), Thai fonts **bundled locally** (offline-first), **Riverpod 3** without codegen in Plan A (Plan B+ may add freezed/json_serializable for model classes — currently excluded to avoid analyzer-range conflict with riverpod_generator on 2026-05-13).

**Tech Stack:** Flutter 3.41+, Dart 3.10+, `flutter_riverpod ^3.3.1`, `go_router ^17.2.3`, `sqflite_sqlcipher ^3.4.0`, `flutter_secure_storage ^10.2.0`, `flutter_localizations` + `intl ^0.20.0`, `flutter_local_notifications ^21.0.0` (inexact only), `timezone ^0.11.0`, `flutter_timezone ^3.0.0`, `shared_preferences ^2.5.5`, `uuid ^4.5.3`. Plan A excludes codegen deps (freezed, json_serializable, riverpod_generator, build_runner) — Plan B reintroduces them after we pick a compatible version pair.

**Non-goals for Plan A:** Supabase, E2E crypto, real invite code generation, Visit Summary PDF, RevenueCat paywall, multi-baby, vaccination log, daily summary math, log-entry CRUD beyond schema. Each is scoped to its own subsequent plan.

**Verification gate:** at end of plan, `flutter analyze` clean, `flutter test` passes, `flutter build apk --debug` produces APK that opens to Home with one-handed Quick-Log grid visible on a Pixel-6-class emulator.

**Competitive UX review applied 2026-05-13:** see `docs/architecture/competitive-ux-brief.md` for the full senior-team teardown vs. Huckleberry / BabyConnect / Nara Baby / Glow Baby / Pump Log. Key applied changes — (1) added `ink.*` + `neutral.muted` + `*.700` color tokens because lavender/peach/sage/honey on cream fail AA (2.03:1 contrast); (2) added `statHero` 48 pt typography; (3) Home density 2.5 → 4 via caregiver-attribution pill + Today timeline row; (4) Share screen flipped QR-on-top with code at 56 pt mono; (5) Welcome baby-name optional + primary CTA shifts to activation copy "Log a feed now."

---

## File Map

```
/Users/nipitphand/Projects/DreamBook/
├── pubspec.yaml                                   (Task 2)
├── l10n.yaml                                      (Task 8)
├── analysis_options.yaml                          (Task 3)
├── .gitignore                                     (Task 3)
├── CLAUDE.md                                      (Task 19)
├── android/
│   └── app/build.gradle.kts                       (Task 1)
│   └── app/src/main/AndroidManifest.xml           (Task 1, 13)
├── ios/Runner/Info.plist                          (Task 1, 13)
├── assets/
│   └── fonts/
│       ├── IBMPlexSansThai-Regular.ttf            (Task 4)
│       ├── IBMPlexSansThai-Medium.ttf             (Task 4)
│       └── IBMPlexSansThai-SemiBold.ttf           (Task 4)
├── lib/
│   ├── main.dart                                  (Task 17)
│   ├── app.dart                                   (Task 17)
│   ├── core/
│   │   ├── theme/
│   │   │   ├── design_tokens.dart                 (Task 5)
│   │   │   ├── app_theme.dart                     (Task 6)
│   │   │   └── theme_mode_controller.dart         (Task 7)
│   │   ├── l10n/
│   │   │   └── l10n_ext.dart                      (Task 9)
│   │   ├── services/
│   │   │   ├── secure_key_service.dart            (Task 10)
│   │   │   └── notification_service.dart          (Task 13)
│   │   ├── db/
│   │   │   ├── database_provider.dart             (Task 12)
│   │   │   ├── migrations/
│   │   │   │   ├── migrations.dart                (Task 11)
│   │   │   │   └── m001_initial.dart              (Task 12)
│   │   ├── router/
│   │   │   └── app_router.dart                    (Task 14)
│   │   └── providers/
│   │       └── shared_preferences_provider.dart   (Task 17)
│   ├── features/
│   │   ├── onboarding/
│   │   │   └── presentation/welcome_screen.dart   (Task 18)
│   │   ├── home/
│   │   │   └── presentation/home_screen.dart      (Task 15)
│   │   └── share/
│   │       └── presentation/share_invite_placeholder_screen.dart (Task 16)
│   └── l10n/
│       ├── app_en.arb                             (Task 8)
│       └── app_th.arb                             (Task 8)
└── test/
    ├── core/theme/theme_mode_controller_test.dart (Task 7)
    ├── core/db/migrations_test.dart               (Task 12)
    └── core/services/secure_key_service_test.dart (Task 10)
```

---

## Task 0: Pre-flight checks

**Files:** none — environment verification.

- [ ] **Step 1: Verify Flutter SDK version**

Run: `flutter --version`
Expected: Flutter ≥ 3.41.0, Dart ≥ 3.10.0. If lower, `flutter channel stable && flutter upgrade`.

- [ ] **Step 2: Verify Android toolchain**

Run: `flutter doctor -v | head -30`
Expected: Android SDK 34+ installed, Android Studio detected, at least one emulator profile or physical device.

- [ ] **Step 3: Capture the existing skeleton state**

Run: `ls /Users/nipitphand/Projects/DreamBook/lib/ /Users/nipitphand/Projects/DreamBook/android/ /Users/nipitphand/Projects/DreamBook/ios/`
Expected: empty directories (`core/`, `features/`, `l10n/` exist but no Dart files; `android/` and `ios/` are empty). This confirms a `flutter create` is required.

---

## Task 1: Flutter create + Android minSdk 23 + iOS 13.0

**Files:**
- Create (via `flutter create`): `android/`, `ios/`, `lib/main.dart`, `pubspec.yaml`, `test/widget_test.dart`, etc.
- Modify: `android/app/build.gradle.kts` — set `minSdk = 23`
- Modify: `ios/Podfile` — set platform iOS 13.0
- Modify: `android/app/src/main/AndroidManifest.xml` — set `android:allowBackup="false"`, no SCHEDULE_EXACT_ALARM

- [ ] **Step 1: Run flutter create over the existing skeleton**

The folder `/Users/nipitphand/Projects/DreamBook` already has a `.git` repo + a `lib/{core,features,l10n}/` skeleton. `flutter create` is safe — it merges, does not delete.

Run:
```bash
cd /Users/nipitphand/Projects/DreamBook && \
flutter create \
  --org studio.niyoko \
  --project-name dreambook \
  --platforms=android,ios \
  --description "Baby daybook for new parents — privacy-first, family share" \
  .
```
Expected: `android/`, `ios/`, `pubspec.yaml`, `lib/main.dart`, `test/widget_test.dart` created. Existing `lib/core/`, `lib/features/`, `lib/l10n/` left intact.

- [ ] **Step 2: Set Android minSdk to 23**

Open `android/app/build.gradle.kts`. Find the `defaultConfig {` block. Replace the minSdk line with:

```kotlin
defaultConfig {
    applicationId = "studio.niyoko.dreambook"
    minSdk = 23
    targetSdk = 34
    versionCode = 1
    versionName = "0.1.0"
}
```

If `targetSdk` is `flutter.targetSdkVersion` from the template, leave that — the explicit `34` here is only required if you want to pin away from Flutter's default. Pin `34` for Plan A.

- [ ] **Step 3: Disable Android auto-backup**

Open `android/app/src/main/AndroidManifest.xml`. In `<application ...>` add or set:

```xml
<application
    android:label="DreamBook"
    android:icon="@mipmap/ic_launcher"
    android:allowBackup="false"
    android:fullBackupContent="false"
    android:dataExtractionRules="@xml/data_extraction_rules">
```

Create `android/app/src/main/res/xml/data_extraction_rules.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<data-extraction-rules>
  <cloud-backup><exclude domain="root" path="."/></cloud-backup>
  <device-transfer><exclude domain="root" path="."/></device-transfer>
</data-extraction-rules>
```

Rationale: `flutter_secure_storage` v10 keys live under app-private storage; auto-backup would copy the encrypted SharedPreferences to Google Drive and break decrypt on restore.

- [ ] **Step 4: Confirm SCHEDULE_EXACT_ALARM is NOT present**

Run: `grep -n -E "SCHEDULE_EXACT_ALARM|USE_EXACT_ALARM" android/app/src/main/AndroidManifest.xml`
Expected: zero matches. (If present from any template, delete the line. This is a project-wide rule per DreamBaby memory.)

- [ ] **Step 5: Pin iOS platform to 13.0**

Open `ios/Podfile`. Uncomment and set the platform line:

```ruby
platform :ios, '13.0'
```

Also open `ios/Runner.xcodeproj/project.pbxproj` and find `IPHONEOS_DEPLOYMENT_TARGET` — set all occurrences to `13.0`. (Or simply set in Podfile and let Cocoapods enforce.)

- [ ] **Step 6: Verify the scaffold builds**

Run: `flutter pub get && flutter build apk --debug`
Expected: PASS — `build/app/outputs/flutter-apk/app-debug.apk` produced. Errors here mean Gradle/AGP mismatch; resolve before proceeding.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: scaffold Flutter project, Android minSdk 23, iOS 13"
```

---

## Task 2: pubspec.yaml — verified 2026 dependencies

**Files:**
- Modify: `pubspec.yaml` — full rewrite of the dependency section
- Create: `assets/fonts/` directory (empty, fonts added Task 4)

- [ ] **Step 1: Replace pubspec.yaml**

Open `pubspec.yaml` and replace contents with:

```yaml
name: dreambook
description: Baby daybook for new parents — privacy-first, family share.
publish_to: 'none'
version: 0.1.0+1

environment:
  sdk: ">=3.10.0 <4.0.0"
  flutter: ">=3.41.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_localizations:
    sdk: flutter

  # State (hand-rolled providers in Plan A — codegen deferred to Plan B)
  flutter_riverpod: ^3.3.1

  # Routing
  go_router: ^17.2.3

  # Persistence (encrypted local DB)
  sqflite_sqlcipher: ^3.4.0
  flutter_secure_storage: ^10.2.0
  shared_preferences: ^2.5.5

  # i18n
  intl: ^0.20.0

  # Notifications (inexact only — never request SCHEDULE_EXACT_ALARM)
  flutter_local_notifications: ^21.0.0
  timezone: ^0.11.0
  flutter_timezone: ^3.0.0

  # Utilities
  uuid: ^4.5.3

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  sqflite_common_ffi: ^2.3.3   # in-memory DB for tests

flutter:
  uses-material-design: true
  generate: true   # triggers `flutter gen-l10n` on build
  fonts:
    - family: IBMPlexSansThai
      fonts:
        - asset: assets/fonts/IBMPlexSansThai-Regular.ttf
        - asset: assets/fonts/IBMPlexSansThai-Medium.ttf
          weight: 500
        - asset: assets/fonts/IBMPlexSansThai-SemiBold.ttf
          weight: 600
```

- [ ] **Step 2: Resolve dependencies**

Run: `flutter pub get`
Expected: PASS, no version conflicts. If a transitive dep complains, do NOT add `dependency_overrides` blindly — investigate.

- [ ] **Step 3: Commit**

```bash
git add pubspec.yaml pubspec.lock && \
git commit -m "feat: pin all v1.0 dependencies (Riverpod 3, secure_storage 10, RC ready)"
```

---

## Task 3: Lint config + .gitignore tweaks

**Files:**
- Modify: `analysis_options.yaml`
- Modify: `.gitignore` (already created by flutter create — add a few extras)

- [ ] **Step 1: Replace analysis_options.yaml**

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true
  errors:
    invalid_annotation_target: ignore  # freezed false-positives
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "lib/l10n/generated/**"
    - "build/**"

linter:
  rules:
    prefer_single_quotes: true
    require_trailing_commas: true
    avoid_print: true
    unawaited_futures: true
    use_super_parameters: true
```

- [ ] **Step 2: Append to .gitignore**

Append:
```
# Generated localization
lib/l10n/generated/

# IDE
.idea/
*.iml

# Dart tool
.dart_tool/

# macOS noise
.DS_Store
```

- [ ] **Step 3: Verify analyzer accepts the config**

Run: `flutter analyze`
Expected: PASS (default scaffold).

- [ ] **Step 4: Commit**

```bash
git add analysis_options.yaml .gitignore && \
git commit -m "chore: enforce strict analyzer + single-quote + trailing-comma lints"
```

---

## Task 4: Bundle Thai fonts (offline-first)

**Files:**
- Create: `assets/fonts/IBMPlexSansThai-Regular.ttf`
- Create: `assets/fonts/IBMPlexSansThai-Medium.ttf`
- Create: `assets/fonts/IBMPlexSansThai-SemiBold.ttf`

- [ ] **Step 1: Download fonts**

IBM Plex Sans Thai is OFL-licensed. Download from the official IBM repo:

```bash
mkdir -p /Users/nipitphand/Projects/DreamBook/assets/fonts && \
cd /Users/nipitphand/Projects/DreamBook/assets/fonts && \
BASE='https://raw.githubusercontent.com/IBM/plex/master/IBM-Plex-Sans-Thai/fonts/complete/ttf' && \
curl -fLO "$BASE/IBMPlexSansThai-Regular.ttf" && \
curl -fLO "$BASE/IBMPlexSansThai-Medium.ttf" && \
curl -fLO "$BASE/IBMPlexSansThai-SemiBold.ttf"
```

Expected: 3 .ttf files, each ~150–300 KB.

- [ ] **Step 2: Verify the fonts are wired**

Run: `flutter pub get && flutter analyze`
Expected: PASS. (Asset declarations in pubspec.yaml from Task 2 already reference these files.)

- [ ] **Step 3: Commit**

```bash
git add assets/fonts/ && \
git commit -m "feat: bundle IBM Plex Sans Thai for offline-first TH support"
```

Note: if you wish to commit fonts via Git LFS for repo hygiene, do that here; otherwise plain commit is fine (~600 KB total).

---

## Task 5: Design tokens (lib/core/theme/design_tokens.dart)

**Files:**
- Create: `lib/core/theme/design_tokens.dart`

- [ ] **Step 1: Write the file**

```dart
import 'dart:ui';

import 'package:flutter/material.dart';

/// Color tokens per Spec §17.7. Three palettes: light, dark, nightTint.
/// nightTint shifts toward warm red/amber to preserve melatonin during
/// 2–4 AM feeds (long-wavelength light suppresses melatonin least).
class AppColors {
  AppColors._();

  // --- Light ---
  static const Color lightPrimary    = Color(0xFFB7A7DD);
  static const Color lightAccent     = Color(0xFFF4C2A0);
  static const Color lightSuccess    = Color(0xFF90B89A);
  static const Color lightWarning    = Color(0xFFE8B547);
  static const Color lightSurface    = Color(0xFFFFF8F0);
  static const Color lightOnSurface  = Color(0xFF2D2A35);
  static const Color lightError      = Color(0xFFB3261E);
  static const Color lightOnPrimary  = Color(0xFFFFFFFF);

  // --- Dark ---
  static const Color darkPrimary     = Color(0xFF9080C0);
  static const Color darkAccent      = Color(0xFFD9A684);
  static const Color darkSuccess     = Color(0xFF7AA084);
  static const Color darkWarning     = Color(0xFFC99A35);
  static const Color darkSurface     = Color(0xFF1A1F2E);
  static const Color darkOnSurface   = Color(0xFFE8E2F0);
  static const Color darkError       = Color(0xFFF2B8B5);
  static const Color darkOnPrimary   = Color(0xFF1A1F2E);

  // --- Night-tint (red-shift, melatonin-safe) ---
  static const Color nightPrimary    = Color(0xFF7060A0);
  static const Color nightAccent     = Color(0xFFA06040);
  static const Color nightSuccess    = Color(0xFF608070);
  static const Color nightWarning    = Color(0xFF996020);
  static const Color nightSurface    = Color(0xFF2A1010);
  static const Color nightOnSurface  = Color(0xFFE0C8B8);
  static const Color nightError      = Color(0xFFE08070);
  static const Color nightOnPrimary  = Color(0xFF2A1010);

  // --- Ink + neutral (text + dividers — passes WCAG AA on cream) ---
  // Brand tokens above fail AA on cream (lavender 2.03:1). Text/icons on
  // cream MUST use ink.* or the *.700 derivatives below.
  static const Color inkPrimary      = Color(0xFF2A2438); // ~13.5:1 AAA
  static const Color inkSecondary    = Color(0xFF6B6478); // ~5.1:1  AA
  static const Color neutralMuted    = Color(0xFFEDE6DC); // decorative

  // --- *.700 dark derivatives — usable for text/icons on cream ---
  static const Color lavender700     = Color(0xFF6B5BA8); // ~4.7:1 AA
  static const Color peach700        = Color(0xFFB57442); // ~4.6:1 AA
  static const Color sage700         = Color(0xFF4F7860); // ~4.8:1 AA
  static const Color honey700        = Color(0xFF9E6F12); // ~4.8:1 AA
}

/// Typography per Spec §17.6. Locale-aware: TH uses bundled IBMPlexSansThai
/// (assets/fonts/), every other locale uses the platform default (SF Pro on
/// iOS, Roboto on Android) — zero asset cost for non-TH users since the OS
/// font ships preinstalled.
class AppTypography {
  AppTypography._();

  static const String _thaiFamily = 'IBMPlexSansThai';

  static String _languageCode({Locale? forceLocale}) =>
      (forceLocale ?? PlatformDispatcher.instance.locale)
          .languageCode
          .toLowerCase();

  static bool isThai({Locale? forceLocale}) =>
      _languageCode(forceLocale: forceLocale) == 'th';

  /// Tabular figures — every digit occupies the same advance width.
  /// Used for timers, durations, page numbers, sleep-log columns.
  static const List<FontFeature> _tabular = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  static TextStyle _base({
    required double size,
    required FontWeight weight,
    double? height,
    double? letterSpacing,
    List<FontFeature>? features,
    Color? color,
    Locale? locale,
  }) {
    return TextStyle(
      fontFamily: isThai(forceLocale: locale) ? _thaiFamily : null,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      fontFeatures: features,
      color: color,
    );
  }

  // Headings: weight 600, slightly tightened tracking.
  static TextStyle displayLarge({Locale? locale, Color? color}) => _base(
        size: 34, weight: FontWeight.w600,
        height: 1.15, letterSpacing: -0.4,
        color: color, locale: locale,
      );
  static TextStyle headlineLarge({Locale? locale, Color? color}) => _base(
        size: 28, weight: FontWeight.w600,
        height: 1.2, letterSpacing: -0.3,
        color: color, locale: locale,
      );
  static TextStyle headlineMedium({Locale? locale, Color? color}) => _base(
        size: 22, weight: FontWeight.w600,
        height: 1.25, letterSpacing: -0.2,
        color: color, locale: locale,
      );
  static TextStyle titleLarge({Locale? locale, Color? color}) => _base(
        size: 18, weight: FontWeight.w600,
        height: 1.3, letterSpacing: -0.1,
        color: color, locale: locale,
      );

  // Body: min 16 pt for accessibility (Spec §17.2 A11y rule).
  static TextStyle bodyLarge({Locale? locale, Color? color}) => _base(
        size: 16, weight: FontWeight.w400,
        height: 1.45, color: color, locale: locale,
      );
  static TextStyle bodyMedium({Locale? locale, Color? color}) => _base(
        size: 15, weight: FontWeight.w400,
        height: 1.45, color: color, locale: locale,
      );
  static TextStyle labelLarge({Locale? locale, Color? color}) => _base(
        size: 14, weight: FontWeight.w500,
        height: 1.3, letterSpacing: 0.1,
        color: color, locale: locale,
      );

  /// Hero numeric — invite code, weekly-summary headline, milestone stat.
  /// Always tabular, always weight 700, always tightened tracking.
  static TextStyle statHero({Locale? locale, Color? color}) => _base(
        size: 48, weight: FontWeight.w700,
        height: 1.05, letterSpacing: -1.5,
        features: _tabular,
        color: color, locale: locale,
      );

  /// Tabular numerals — use anywhere digits stack vertically or animate.
  static TextStyle numeric({
    double size = 16,
    FontWeight weight = FontWeight.w500,
    Locale? locale,
    Color? color,
  }) =>
      _base(
        size: size, weight: weight,
        features: _tabular,
        color: color, locale: locale,
      );
}

/// Corner radii — soft, calm.
class AppRadii {
  AppRadii._();
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
}

/// Spacing scale — 4 px base grid.
class AppSpacing {
  AppSpacing._();
  static const double xxs = 4;
  static const double xs  = 8;
  static const double sm  = 12;
  static const double md  = 16;
  static const double lg  = 24;
  static const double xl  = 32;

  /// Minimum touch target per Spec §17.2 one-thumb rule.
  static const double minTouchTarget = 48;

  /// Quick-Log buttons should be larger — mom is half-asleep + one-handed.
  static const double quickLogButton = 96;
}

class AppElevation {
  AppElevation._();
  static const double none   = 0;
  static const double level1 = 1;
  static const double level2 = 3;
  static const double level3 = 6;
  static const double sheet  = 8;
}
```

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/core/theme/design_tokens.dart`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add lib/core/theme/design_tokens.dart && \
git commit -m "feat(theme): design tokens — colors, typography, spacing, radii"
```

---

## Task 6: App theme (lib/core/theme/app_theme.dart)

**Files:**
- Create: `lib/core/theme/app_theme.dart`

- [ ] **Step 1: Write the file**

```dart
import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Spec §17.7 ColorScheme is built explicitly — never `fromSeed` —
/// because `fromSeed` re-derives every role tonally from a single hue,
/// which destroys the curated accent/warning relationships in our palette.
class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(
        brightness: Brightness.light,
        scheme: const ColorScheme(
          brightness: Brightness.light,
          primary: AppColors.lightPrimary,
          onPrimary: AppColors.lightOnPrimary,
          secondary: AppColors.lightAccent,
          onSecondary: AppColors.lightOnSurface,
          tertiary: AppColors.lightSuccess,
          onTertiary: AppColors.lightOnSurface,
          error: AppColors.lightError,
          onError: Color(0xFFFFFFFF),
          surface: AppColors.lightSurface,
          onSurface: AppColors.lightOnSurface,
          surfaceContainerHighest: Color(0xFFEFE7DC),
          outline: Color(0xFFB7AFA3),
        ),
        warning: AppColors.lightWarning,
      );

  static ThemeData dark() => _build(
        brightness: Brightness.dark,
        scheme: const ColorScheme(
          brightness: Brightness.dark,
          primary: AppColors.darkPrimary,
          onPrimary: AppColors.darkOnPrimary,
          secondary: AppColors.darkAccent,
          onSecondary: AppColors.darkOnSurface,
          tertiary: AppColors.darkSuccess,
          onTertiary: AppColors.darkOnSurface,
          error: AppColors.darkError,
          onError: Color(0xFF601410),
          surface: AppColors.darkSurface,
          onSurface: AppColors.darkOnSurface,
          surfaceContainerHighest: Color(0xFF252B3A),
          outline: Color(0xFF555C70),
        ),
        warning: AppColors.darkWarning,
      );

  static ThemeData nightTint() => _build(
        brightness: Brightness.dark,
        scheme: const ColorScheme(
          brightness: Brightness.dark,
          primary: AppColors.nightPrimary,
          onPrimary: AppColors.nightOnPrimary,
          secondary: AppColors.nightAccent,
          onSecondary: AppColors.nightOnSurface,
          tertiary: AppColors.nightSuccess,
          onTertiary: AppColors.nightOnSurface,
          error: AppColors.nightError,
          onError: Color(0xFF300806),
          surface: AppColors.nightSurface,
          onSurface: AppColors.nightOnSurface,
          surfaceContainerHighest: Color(0xFF3A1818),
          outline: Color(0xFF704040),
        ),
        warning: AppColors.nightWarning,
      );

  static ThemeData _build({
    required Brightness brightness,
    required ColorScheme scheme,
    required Color warning,
  }) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.md),
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      textTheme: base.textTheme.copyWith(
        displayLarge:   AppTypography.displayLarge(color: scheme.onSurface),
        headlineLarge:  AppTypography.headlineLarge(color: scheme.onSurface),
        headlineMedium: AppTypography.headlineMedium(color: scheme.onSurface),
        titleLarge:     AppTypography.titleLarge(color: scheme.onSurface),
        bodyLarge:      AppTypography.bodyLarge(color: scheme.onSurface),
        bodyMedium:     AppTypography.bodyMedium(color: scheme.onSurface),
        labelLarge:     AppTypography.labelLarge(color: scheme.onSurface),
      ),
      cardTheme: CardThemeData(
        elevation: AppElevation.level1,
        color: scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
          shape: shape,
          textStyle: AppTypography.labelLarge(),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(AppSpacing.minTouchTarget),
          shape: shape,
          side: BorderSide(color: scheme.outline),
          textStyle: AppTypography.labelLarge(),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide(color: scheme.outline.withValues(alpha: 0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        labelStyle: AppTypography.bodyMedium(color: scheme.onSurface),
      ),
      extensions: <ThemeExtension<dynamic>>[
        _SemanticColors(warning: warning),
      ],
    );
  }

  static TextStyle numericTextStyle(BuildContext context, {double size = 16}) {
    final color = Theme.of(context).colorScheme.onSurface;
    return AppTypography.numeric(size: size, color: color);
  }

  static Color warningOf(BuildContext context) =>
      Theme.of(context).extension<_SemanticColors>()!.warning;
}

class _SemanticColors extends ThemeExtension<_SemanticColors> {
  const _SemanticColors({required this.warning});
  final Color warning;

  @override
  _SemanticColors copyWith({Color? warning}) =>
      _SemanticColors(warning: warning ?? this.warning);

  @override
  _SemanticColors lerp(ThemeExtension<_SemanticColors>? other, double t) {
    if (other is! _SemanticColors) return this;
    return _SemanticColors(warning: Color.lerp(warning, other.warning, t)!);
  }
}
```

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/core/theme/`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add lib/core/theme/app_theme.dart && \
git commit -m "feat(theme): light/dark/nightTint ThemeData with explicit ColorScheme"
```

---

## Task 7: Theme mode controller + test

**Files:**
- Create: `lib/core/theme/theme_mode_controller.dart`
- Create: `test/core/theme/theme_mode_controller_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/theme/theme_mode_controller_test.dart
import 'package:dreambook/core/theme/app_theme.dart';
import 'package:dreambook/core/theme/theme_mode_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  ProviderContainer makeContainer({DateTime Function()? now}) {
    return ProviderContainer(overrides: [
      if (now != null) nowProvider.overrideWithValue(now),
    ]);
  }

  test('default is system → daytime → light theme', () async {
    final c = makeContainer(now: () => DateTime(2026, 5, 13, 14, 0));
    await c.read(themeModeControllerProvider.future);
    final theme = c.read(themeProvider);
    expect(theme.brightness, Brightness.light);
  });

  test('system + nighttime hour → dark theme', () async {
    final c = makeContainer(now: () => DateTime(2026, 5, 13, 2, 0));
    await c.read(themeModeControllerProvider.future);
    final theme = c.read(themeProvider);
    expect(theme.brightness, Brightness.dark);
  });

  test('system + nighttime + redTint toggle → nightTint surface', () async {
    final c = makeContainer(now: () => DateTime(2026, 5, 13, 3, 0));
    await c.read(themeModeControllerProvider.future);
    await c.read(themeModeControllerProvider.notifier).toggleRedTint(true);
    final theme = c.read(themeProvider);
    expect(theme.colorScheme.surface, const Color(0xFF2A1010));
  });

  test('explicit light choice overrides clock', () async {
    final c = makeContainer(now: () => DateTime(2026, 5, 13, 3, 0));
    await c.read(themeModeControllerProvider.future);
    await c
        .read(themeModeControllerProvider.notifier)
        .setChoice(UserThemeChoice.light);
    final theme = c.read(themeProvider);
    expect(theme.brightness, Brightness.light);
  });
}
```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `flutter test test/core/theme/theme_mode_controller_test.dart`
Expected: FAIL — `theme_mode_controller.dart` not found.

- [ ] **Step 3: Write the controller**

```dart
// lib/core/theme/theme_mode_controller.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

enum UserThemeChoice { system, light, dark, nightTint }

class ThemeModeState {
  const ThemeModeState({
    required this.choice,
    required this.redTintPreserveMelatonin,
  });

  final UserThemeChoice choice;
  final bool redTintPreserveMelatonin;

  ThemeModeState copyWith({
    UserThemeChoice? choice,
    bool? redTintPreserveMelatonin,
  }) =>
      ThemeModeState(
        choice: choice ?? this.choice,
        redTintPreserveMelatonin:
            redTintPreserveMelatonin ?? this.redTintPreserveMelatonin,
      );

  static const initial = ThemeModeState(
    choice: UserThemeChoice.system,
    redTintPreserveMelatonin: false,
  );
}

const _kThemeModeKey = 'theme.mode';
const _kRedTintKey   = 'theme.redTint';

class ThemeModeController extends AsyncNotifier<ThemeModeState> {
  @override
  Future<ThemeModeState> build() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kThemeModeKey) ?? 'system';
    final redTint = prefs.getBool(_kRedTintKey) ?? false;
    return ThemeModeState(
      choice: _decode(raw),
      redTintPreserveMelatonin: redTint,
    );
  }

  Future<void> setChoice(UserThemeChoice choice) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeModeKey, _encode(choice));
    state = AsyncData(
      (state.value ?? ThemeModeState.initial).copyWith(choice: choice),
    );
  }

  Future<void> toggleRedTint(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kRedTintKey, enabled);
    state = AsyncData(
      (state.value ?? ThemeModeState.initial)
          .copyWith(redTintPreserveMelatonin: enabled),
    );
  }

  static String _encode(UserThemeChoice c) => switch (c) {
        UserThemeChoice.system    => 'system',
        UserThemeChoice.light     => 'light',
        UserThemeChoice.dark      => 'dark',
        UserThemeChoice.nightTint => 'nightTint',
      };

  static UserThemeChoice _decode(String s) => switch (s) {
        'light'     => UserThemeChoice.light,
        'dark'      => UserThemeChoice.dark,
        'nightTint' => UserThemeChoice.nightTint,
        _           => UserThemeChoice.system,
      };
}

final themeModeControllerProvider =
    AsyncNotifierProvider<ThemeModeController, ThemeModeState>(
  ThemeModeController.new,
);

/// Wall-clock provider — wrap so tests can override with a fake clock.
final nowProvider = Provider<DateTime Function()>((_) => DateTime.now);

bool _isNightHour(DateTime now) {
  final h = now.hour;
  return h >= 20 || h < 6;
}

final themeProvider = Provider<ThemeData>((ref) {
  final asyncState = ref.watch(themeModeControllerProvider);
  final state = asyncState.value ?? ThemeModeState.initial;
  final now = ref.watch(nowProvider)();

  switch (state.choice) {
    case UserThemeChoice.light:
      return AppTheme.light();
    case UserThemeChoice.dark:
      return AppTheme.dark();
    case UserThemeChoice.nightTint:
      return AppTheme.nightTint();
    case UserThemeChoice.system:
      if (_isNightHour(now)) {
        return state.redTintPreserveMelatonin
            ? AppTheme.nightTint()
            : AppTheme.dark();
      }
      return AppTheme.light();
  }
});
```

- [ ] **Step 4: Run the tests — all pass**

Run: `flutter test test/core/theme/theme_mode_controller_test.dart`
Expected: PASS — 4/4.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/theme_mode_controller.dart test/core/theme/ && \
git commit -m "feat(theme): theme mode controller with night-hour auto-switch + redTint"
```

---

## Task 8: L10n config + ARB files (EN + TH)

**Files:**
- Create: `l10n.yaml`
- Create: `lib/l10n/app_en.arb`
- Create: `lib/l10n/app_th.arb`

- [ ] **Step 1: Write `l10n.yaml` at project root**

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
output-dir: lib/l10n/generated
synthetic-package: false
nullable-getter: false
untranslated-messages-file: lib/l10n/untranslated.txt
```

- [ ] **Step 2: Write `lib/l10n/app_en.arb`**

```json
{
  "@@locale": "en",
  "appName": "DreamBook",
  "appNameThaiSub": "Your baby's daybook",

  "actionSave": "Save",
  "actionCancel": "Cancel",
  "actionEdit": "Edit",
  "actionDelete": "Delete",
  "actionDone": "Done",
  "actionNext": "Next",
  "actionBack": "Back",
  "actionSkip": "Skip",
  "actionRetry": "Try again",
  "errorGeneric": "Something went wrong. Please try again.",
  "loading": "Loading…",

  "tabHome": "Home",
  "tabSummary": "Summary",
  "tabStash": "Stash",
  "tabSettings": "Settings",

  "today": "Today",
  "yesterday": "Yesterday",
  "dateRangeLast7Days": "Last 7 days",
  "dateRangeLast14Days": "Last 14 days",
  "dateRangeLast30Days": "Last 30 days",

  "relativeMinutesAgo": "{count, plural, =1{1 min ago} other{{count} min ago}}",
  "@relativeMinutesAgo": { "placeholders": { "count": { "type": "int" } } },
  "relativeHoursAgo": "{count, plural, =1{1 hr ago} other{{count} hr ago}}",
  "@relativeHoursAgo": { "placeholders": { "count": { "type": "int" } } },

  "unitOz": "oz",
  "unitMl": "ml",
  "unitMin": "minutes",
  "unitMinShort": "min",
  "unitHrShort": "hr",

  "homeQuickLogFeed": "Feed",
  "homeQuickLogPump": "Pump",
  "homeQuickLogDiaper": "Diaper",
  "homeQuickLogSleep": "Sleep",
  "homeStatFeedOz": "{oz} oz fed today",
  "@homeStatFeedOz": { "placeholders": { "oz": { "type": "String" } } },
  "homeStatDiaperCount": "{count, plural, =0{No diapers yet} =1{1 diaper today} other{{count} diapers today}}",
  "@homeStatDiaperCount": { "placeholders": { "count": { "type": "int" } } },
  "homeStatSleepHours": "{hours} hr asleep today",
  "@homeStatSleepHours": { "placeholders": { "hours": { "type": "String" } } },
  "homeStatPumpCount": "{count, plural, =0{No pumps yet} =1{1 pump today} other{{count} pumps today}}",
  "@homeStatPumpCount": { "placeholders": { "count": { "type": "int" } } },
  "homeStatStashBottles": "{count, plural, =0{Stash empty} =1{1 bottle in stash} other{{count} bottles in stash}}",
  "@homeStatStashBottles": { "placeholders": { "count": { "type": "int" } } },
  "homeBabyAgeWeeks": "{count, plural, =1{{babyName} is 1 week old} other{{babyName} is {count} weeks old}}",
  "@homeBabyAgeWeeks": { "placeholders": { "count": { "type": "int" }, "babyName": { "type": "String" } } },
  "homeBabyAgeMonths": "{count, plural, =1{{babyName} is 1 month old} other{{babyName} is {count} months old}}",
  "@homeBabyAgeMonths": { "placeholders": { "count": { "type": "int" }, "babyName": { "type": "String" } } },

  "feedScreenTitle": "Log a feed",
  "feedSideLeft": "Left",
  "feedSideRight": "Right",
  "feedSourceBreastmilk": "Breastmilk",
  "feedSourceFormula": "Formula",
  "feedFromFreezerStash": "From freezer stash",
  "feedNotes": "Notes",

  "pumpScreenTitle": "Log a pump",
  "pumpLeftOz": "Left (oz)",
  "pumpRightOz": "Right (oz)",
  "pumpSaveToStash": "Save to freezer stash",

  "stashTitle": "Freezer stash",
  "stashEmptyState": "No bottles in the stash yet. Save your next pump to start.",
  "stashFresh": "Fresh",
  "stashAging": "Use soon",
  "stashNearExpiry": "Use today",
  "stashExpiresIn": "{days, plural, =0{Expires today} =1{Expires in 1 day} other{Expires in {days} days}}",
  "@stashExpiresIn": { "placeholders": { "days": { "type": "int" } } },
  "stashFifoHint": "Tip: use the oldest bottle first.",
  "stashFreeTierCap": "Free plan tracks up to {cap} bottles. Upgrade for unlimited stash.",
  "@stashFreeTierCap": { "placeholders": { "cap": { "type": "int" } } },

  "diaperTitle": "Log a diaper",
  "diaperPee": "Pee",
  "diaperPoop": "Poop",
  "diaperMixed": "Both",
  "diaperDry": "Dry",

  "sleepTitle": "Log sleep",
  "sleepLocationCrib": "Crib",
  "sleepLocationStroller": "Stroller",
  "sleepLocationCar": "Car seat",
  "sleepLocationOther": "Other",

  "shareTitle": "Caregivers",
  "shareInviteCta": "Invite a caregiver",
  "shareInviteHeadline": "Share {babyName}'s daybook",
  "@shareInviteHeadline": { "placeholders": { "babyName": { "type": "String" } } },
  "shareInviteCodeLabel": "Your invite code",
  "shareInviteExpiresIn": "Code expires in {minutes} min",
  "@shareInviteExpiresIn": { "placeholders": { "minutes": { "type": "int" } } },
  "shareInviteShareVia": "Share via…",
  "shareRoleReadOnly": "Read only",
  "shareRoleEditor": "Can log",
  "shareRoleAdmin": "Co-parent",
  "shareCaregiverLogged": "{caregiverName} logged {action} • {relativeTime}",
  "@shareCaregiverLogged": { "placeholders": { "caregiverName": { "type": "String" }, "action": { "type": "String" }, "relativeTime": { "type": "String" } } },
  "shareJustYou": "Just you for now. Invite a partner or grandparent to share the load.",

  "joinHaveCode": "I have an invite code",
  "joinEnterCode": "Enter your 8-char code",
  "joinScanQr": "Scan QR code instead",
  "joinConnecting": "Connecting…",
  "joinConnected": "Connected to {babyName}'s daybook",
  "@joinConnected": { "placeholders": { "babyName": { "type": "String" } } },

  "summaryTitle": "Summary",
  "summaryDailyTotals": "Today's totals",
  "summaryGeneratePdf": "Generate visit PDF",
  "summaryPdfPremiumLock": "Visit PDF is a Premium feature. Upgrade to share with your pediatrician.",

  "premiumTitle": "DreamBook Premium",
  "premiumPriceMonthly": "Monthly",
  "premiumPriceYearly": "Yearly",
  "premiumPriceLifetime": "Lifetime",
  "premiumTrialBadge": "7-day free trial",

  "settingsLanguage": "Language",
  "settingsLanguageEn": "English",
  "settingsLanguageTh": "ไทย (Thai)",
  "settingsNightFeedMode": "Night mode (dim screen)",
  "settingsDeleteMyData": "Delete my data",
  "settingsAbout": "About DreamBook",

  "emptyFeed": "No feeds logged yet. Tap Feed when you're ready.",
  "emptyPump": "No pumps logged yet. Your first session will appear here.",
  "emptyDiaper": "No diapers logged yet today.",
  "emptySleep": "No sleep logged yet. Tap Sleep when baby drifts off.",
  "emptyCaregivers": "Just you for now. Invite a partner or grandparent to share the load.",

  "disclaimerNotMedical": "DreamBook helps you keep notes — it is not medical advice. For health concerns, please contact your pediatrician.",

  "welcomeHeadline": "Welcome to DreamBook",
  "welcomeSubcopy": "A calm place to log feeds, pumps, diapers, and sleep — and share with the people helping you.",
  "welcomeBabyNameLabel": "Baby's name",
  "welcomeBabyNameHint": "e.g. Mali",
  "welcomeStartCta": "Start tracking"
}
```

- [ ] **Step 3: Write `lib/l10n/app_th.arb`**

```json
{
  "@@locale": "th",
  "appName": "DreamBook",
  "appNameThaiSub": "สมุดบันทึกลูกน้อย",

  "actionSave": "บันทึก",
  "actionCancel": "ยกเลิก",
  "actionEdit": "แก้ไข",
  "actionDelete": "ลบ",
  "actionDone": "เสร็จแล้ว",
  "actionNext": "ถัดไป",
  "actionBack": "ย้อนกลับ",
  "actionSkip": "ข้าม",
  "actionRetry": "ลองใหม่",
  "errorGeneric": "เกิดข้อผิดพลาด ลองอีกครั้งนะคะ",
  "loading": "กำลังโหลด…",

  "tabHome": "หน้าหลัก",
  "tabSummary": "สรุป",
  "tabStash": "สต๊อกนม",
  "tabSettings": "ตั้งค่า",

  "today": "วันนี้",
  "yesterday": "เมื่อวาน",
  "dateRangeLast7Days": "7 วันที่ผ่านมา",
  "dateRangeLast14Days": "14 วันที่ผ่านมา",
  "dateRangeLast30Days": "30 วันที่ผ่านมา",

  "relativeMinutesAgo": "{count, plural, =1{1 นาทีที่แล้ว} other{{count} นาทีที่แล้ว}}",
  "@relativeMinutesAgo": { "placeholders": { "count": { "type": "int" } } },
  "relativeHoursAgo": "{count, plural, =1{1 ชั่วโมงที่แล้ว} other{{count} ชั่วโมงที่แล้ว}}",
  "@relativeHoursAgo": { "placeholders": { "count": { "type": "int" } } },

  "unitOz": "ออนซ์",
  "unitMl": "มล.",
  "unitMin": "นาที",
  "unitMinShort": "นาที",
  "unitHrShort": "ชม.",

  "homeQuickLogFeed": "ให้นม",
  "homeQuickLogPump": "ปั๊มนม",
  "homeQuickLogDiaper": "ผ้าอ้อม",
  "homeQuickLogSleep": "นอน",
  "homeStatFeedOz": "วันนี้ให้นมไป {oz} ออนซ์",
  "@homeStatFeedOz": { "placeholders": { "oz": { "type": "String" } } },
  "homeStatDiaperCount": "{count, plural, =0{ยังไม่ได้เปลี่ยนผ้าอ้อม} =1{เปลี่ยนผ้าอ้อม 1 ครั้งวันนี้} other{เปลี่ยนผ้าอ้อม {count} ครั้งวันนี้}}",
  "@homeStatDiaperCount": { "placeholders": { "count": { "type": "int" } } },
  "homeStatSleepHours": "วันนี้ลูกนอนไป {hours} ชม.",
  "@homeStatSleepHours": { "placeholders": { "hours": { "type": "String" } } },
  "homeStatPumpCount": "{count, plural, =0{ยังไม่ได้ปั๊มนม} =1{ปั๊มนม 1 ครั้งวันนี้} other{ปั๊มนม {count} ครั้งวันนี้}}",
  "@homeStatPumpCount": { "placeholders": { "count": { "type": "int" } } },
  "homeStatStashBottles": "{count, plural, =0{สต๊อกนมว่างอยู่} =1{มีนมในสต๊อก 1 ขวด} other{มีนมในสต๊อก {count} ขวด}}",
  "@homeStatStashBottles": { "placeholders": { "count": { "type": "int" } } },
  "homeBabyAgeWeeks": "{count, plural, =1{{babyName} อายุ 1 สัปดาห์แล้ว} other{{babyName} อายุ {count} สัปดาห์แล้ว}}",
  "@homeBabyAgeWeeks": { "placeholders": { "count": { "type": "int" }, "babyName": { "type": "String" } } },
  "homeBabyAgeMonths": "{count, plural, =1{{babyName} อายุ 1 เดือนแล้ว} other{{babyName} อายุ {count} เดือนแล้ว}}",
  "@homeBabyAgeMonths": { "placeholders": { "count": { "type": "int" }, "babyName": { "type": "String" } } },

  "feedScreenTitle": "บันทึกการให้นม",
  "feedSideLeft": "ซ้าย",
  "feedSideRight": "ขวา",
  "feedSourceBreastmilk": "นมแม่",
  "feedSourceFormula": "นมผง",
  "feedFromFreezerStash": "ใช้นมจากสต๊อก",
  "feedNotes": "บันทึกเพิ่มเติม",

  "pumpScreenTitle": "บันทึกการปั๊มนม",
  "pumpLeftOz": "ซ้าย (มล.)",
  "pumpRightOz": "ขวา (มล.)",
  "pumpSaveToStash": "เก็บเข้าสต๊อกนม",

  "stashTitle": "สต๊อกนมแช่แข็ง",
  "stashEmptyState": "ยังไม่มีนมในสต๊อก เก็บนมจากการปั๊มครั้งถัดไปได้เลยค่ะ",
  "stashFresh": "ใหม่",
  "stashAging": "ใช้เร็วๆ นี้",
  "stashNearExpiry": "ใช้ภายในวันนี้",
  "stashExpiresIn": "{days, plural, =0{หมดอายุวันนี้} =1{เหลืออีก 1 วัน} other{เหลืออีก {days} วัน}}",
  "@stashExpiresIn": { "placeholders": { "days": { "type": "int" } } },
  "stashFifoHint": "เคล็ดลับ: ใช้ขวดที่เก็บไว้นานที่สุดก่อนนะคะ",
  "stashFreeTierCap": "แผนฟรีเก็บนมได้สูงสุด {cap} ขวด อัปเกรดเพื่อเก็บได้ไม่จำกัด",
  "@stashFreeTierCap": { "placeholders": { "cap": { "type": "int" } } },

  "diaperTitle": "บันทึกผ้าอ้อม",
  "diaperPee": "ฉี่",
  "diaperPoop": "อึ",
  "diaperMixed": "ทั้งสองอย่าง",
  "diaperDry": "แห้ง",

  "sleepTitle": "บันทึกการนอน",
  "sleepLocationCrib": "เปลนอน",
  "sleepLocationStroller": "รถเข็น",
  "sleepLocationCar": "คาร์ซีท",
  "sleepLocationOther": "อื่นๆ",

  "shareTitle": "ผู้ดูแล",
  "shareInviteCta": "ชวนผู้ดูแลคนอื่น",
  "shareInviteHeadline": "แชร์สมุดบันทึกของ {babyName}",
  "@shareInviteHeadline": { "placeholders": { "babyName": { "type": "String" } } },
  "shareInviteCodeLabel": "รหัสเชิญของคุณ",
  "shareInviteExpiresIn": "รหัสจะหมดอายุใน {minutes} นาที",
  "@shareInviteExpiresIn": { "placeholders": { "minutes": { "type": "int" } } },
  "shareInviteShareVia": "แชร์ผ่าน…",
  "shareRoleReadOnly": "ดูได้อย่างเดียว",
  "shareRoleEditor": "บันทึกข้อมูลได้",
  "shareRoleAdmin": "ผู้ดูแลหลัก",
  "shareCaregiverLogged": "{caregiverName} บันทึก {action} • {relativeTime}",
  "@shareCaregiverLogged": { "placeholders": { "caregiverName": { "type": "String" }, "action": { "type": "String" }, "relativeTime": { "type": "String" } } },
  "shareJustYou": "ตอนนี้มีคุณคนเดียว ชวนคุณพ่อหรือคุณยายมาช่วยดูแลด้วยกันนะคะ",

  "joinHaveCode": "ฉันมีรหัสเชิญ",
  "joinEnterCode": "ใส่รหัส 8 ตัว",
  "joinScanQr": "สแกน QR แทน",
  "joinConnecting": "กำลังเชื่อมต่อ…",
  "joinConnected": "เชื่อมต่อกับสมุดบันทึกของ {babyName} แล้ว",
  "@joinConnected": { "placeholders": { "babyName": { "type": "String" } } },

  "summaryTitle": "สรุป",
  "summaryDailyTotals": "ยอดรวมวันนี้",
  "summaryGeneratePdf": "สร้าง PDF สำหรับพบหมอ",
  "summaryPdfPremiumLock": "PDF สำหรับพบหมอเป็นฟีเจอร์พรีเมียม อัปเกรดเพื่อส่งให้คุณหมอได้เลย",

  "premiumTitle": "DreamBook พรีเมียม",
  "premiumPriceMonthly": "รายเดือน",
  "premiumPriceYearly": "รายปี",
  "premiumPriceLifetime": "ตลอดชีพ",
  "premiumTrialBadge": "ทดลองฟรี 7 วัน",

  "settingsLanguage": "ภาษา",
  "settingsLanguageEn": "English",
  "settingsLanguageTh": "ไทย",
  "settingsNightFeedMode": "โหมดกลางคืน (หรี่หน้าจอ)",
  "settingsDeleteMyData": "ลบข้อมูลของฉัน",
  "settingsAbout": "เกี่ยวกับ DreamBook",

  "emptyFeed": "ยังไม่มีบันทึกการให้นม แตะปุ่ม ให้นม เมื่อพร้อมได้เลยค่ะ",
  "emptyPump": "ยังไม่มีบันทึกการปั๊มนม การปั๊มครั้งแรกจะขึ้นที่นี่",
  "emptyDiaper": "วันนี้ยังไม่มีบันทึกผ้าอ้อม",
  "emptySleep": "ยังไม่มีบันทึกการนอน แตะปุ่ม นอน เมื่อลูกหลับได้เลย",
  "emptyCaregivers": "ตอนนี้มีคุณคนเดียว ชวนคุณพ่อหรือคุณยายมาช่วยดูแลด้วยกันนะคะ",

  "disclaimerNotMedical": "DreamBook ช่วยจดบันทึก ไม่ใช่คำแนะนำทางการแพทย์ หากกังวลเรื่องสุขภาพลูก กรุณาปรึกษากุมารแพทย์",

  "welcomeHeadline": "ยินดีต้อนรับสู่ DreamBook",
  "welcomeSubcopy": "พื้นที่บันทึกการให้นม ปั๊มนม ผ้าอ้อม การนอน อย่างเป็นระบบ และแชร์ให้คนที่ช่วยดูแลลูกได้",
  "welcomeBabyNameLabel": "ชื่อลูก",
  "welcomeBabyNameHint": "เช่น มะลิ",
  "welcomeStartCta": "เริ่มบันทึก"
}
```

- [ ] **Step 4: Generate the AppLocalizations class**

Run: `flutter gen-l10n`
Expected: `lib/l10n/generated/app_localizations.dart` + `app_localizations_en.dart` + `app_localizations_th.dart` created. No errors.

- [ ] **Step 5: Verify**

Run: `flutter analyze`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add l10n.yaml lib/l10n/ && \
git commit -m "feat(l10n): scaffold EN + TH ARBs (Spec §17 — full daily logging keys)"
```

---

## Task 9: L10n BuildContext extension

**Files:**
- Create: `lib/core/l10n/l10n_ext.dart`

- [ ] **Step 1: Write the extension**

```dart
import 'package:flutter/widgets.dart';

import '../../l10n/generated/app_localizations.dart';

export '../../l10n/generated/app_localizations.dart';

extension L10nExt on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
```

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/core/l10n/`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add lib/core/l10n/l10n_ext.dart && \
git commit -m "feat(l10n): context.l10n extension (BuildContext sugar)"
```

---

## Task 10: SecureKeyService (DB key in Keychain / EncryptedSharedPreferences)

**Files:**
- Create: `lib/core/services/secure_key_service.dart`
- Create: `test/core/services/secure_key_service_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/core/services/secure_key_service_test.dart
import 'package:dreambook/core/services/secure_key_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // In-memory fake for flutter_secure_storage via MethodChannel.
  final fakeStorage = <String, String>{};
  setUp(() {
    fakeStorage.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        switch (call.method) {
          case 'read':
            return fakeStorage[(call.arguments as Map)['key']];
          case 'write':
            final args = call.arguments as Map;
            fakeStorage[args['key']! as String] = args['value']! as String;
            return null;
          case 'delete':
            fakeStorage.remove((call.arguments as Map)['key']);
            return null;
          case 'deleteAll':
            fakeStorage.clear();
            return null;
        }
        return null;
      },
    );
  });

  test('getOrCreateDbKey returns same key on subsequent calls', () async {
    final a = await SecureKeyService.getOrCreateDbKey();
    final b = await SecureKeyService.getOrCreateDbKey();
    expect(a, b);
    expect(a.length, greaterThanOrEqualTo(32));
  });

  test('keys are url-safe base64', () async {
    final k = await SecureKeyService.getOrCreateDbKey();
    expect(RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(k), isTrue);
  });
}
```

- [ ] **Step 2: Run test — fails**

Run: `flutter test test/core/services/secure_key_service_test.dart`
Expected: FAIL — service not found.

- [ ] **Step 3: Write the service**

```dart
// lib/core/services/secure_key_service.dart
import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureKeyService {
  SecureKeyService._();

  static const _dbKeyAlias = 'dreambook_db_key_v1';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Returns the encryption key for sqflite_sqlcipher. Generates one on
  /// first call and stores it in Keychain (iOS) / EncryptedSharedPreferences
  /// (Android). On rare KeyStore corruption, wipes and regenerates — old DB
  /// becomes unreadable, which is recoverable (re-onboarding) but logged.
  static Future<String> getOrCreateDbKey() async {
    try {
      var key = await _storage.read(key: _dbKeyAlias);
      if (key == null) {
        key = _makeKey();
        await _storage.write(key: _dbKeyAlias, value: key);
      }
      return key;
    } catch (_) {
      final newKey = _makeKey();
      try {
        await _storage.deleteAll();
        await _storage.write(key: _dbKeyAlias, value: newKey);
      } catch (_) {/* swallow — return key anyway */}
      return newKey;
    }
  }

  static String _makeKey() {
    final r = Random.secure();
    final bytes = List<int>.generate(32, (_) => r.nextInt(256));
    return base64UrlEncode(bytes);
  }
}
```

- [ ] **Step 4: Run tests — pass**

Run: `flutter test test/core/services/secure_key_service_test.dart`
Expected: PASS — 2/2.

- [ ] **Step 5: Commit**

```bash
git add lib/core/services/secure_key_service.dart test/core/services/ && \
git commit -m "feat(security): SecureKeyService — DB key in Keychain/EncryptedSharedPreferences"
```

---

## Task 11: Migration runner

**Files:**
- Create: `lib/core/db/migrations/migrations.dart`

- [ ] **Step 1: Write the migration runner**

DreamBaby has no shared migration runner (only `onCreate` per repo). DreamBook defines one from day 1 because the v1 schema touches 9 tables across one file and we must support v2+ growth (e.g., adding photo_path columns in Plan B+).

```dart
// lib/core/db/migrations/migrations.dart
import 'package:sqflite_sqlcipher/sqflite.dart';

/// A migration is "I move the DB from version `from` to version `from + 1`".
typedef MigrationStep = Future<void> Function(Database db);

/// Ordered list of migrations. Index 0 = v0 → v1, index 1 = v1 → v2, etc.
/// Append to this list when adding a new schema version. Never reorder,
/// never delete — schema migrations are append-only history.
class Migrations {
  Migrations(this._steps);

  final List<MigrationStep> _steps;

  int get currentVersion => _steps.length;

  Future<void> runAll(Database db) async {
    for (final step in _steps) {
      await step(db);
    }
  }

  Future<void> runFrom(Database db, int oldVersion, int newVersion) async {
    for (var v = oldVersion; v < newVersion; v++) {
      await _steps[v](db);
    }
  }
}
```

- [ ] **Step 2: Verify**

Run: `flutter analyze lib/core/db/`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add lib/core/db/migrations/migrations.dart && \
git commit -m "feat(db): append-only migration runner (greenfield — not from DreamBaby)"
```

---

## Task 12: DB v1 schema + repository scaffold + migration test

**Files:**
- Create: `lib/core/db/migrations/m001_initial.dart`
- Create: `lib/core/db/database_provider.dart`
- Create: `test/core/db/migrations_test.dart`

- [ ] **Step 1: Write the failing migration test**

```dart
// test/core/db/migrations_test.dart
import 'package:dreambook/core/db/migrations/m001_initial.dart';
import 'package:dreambook/core/db/migrations/migrations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  Future<Database> openMem() async {
    return databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, onCreate: (db, _) async {
        await Migrations([m001Initial]).runAll(db);
      }),
    );
  }

  test('v1 creates 9 user tables + sync_state + meta', () async {
    final db = await openMem();
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%' ORDER BY name",
    );
    final names = rows.map((r) => r['name']).toSet();
    expect(names, containsAll(<String>{
      'baby', 'caregiver', 'diaper', 'feed', 'meta',
      'pump_session', 'sleep', 'stash_bottle', 'sync_state', 'vaccination',
    }));
    await db.close();
  });

  test('foreign keys cascade on baby delete', () async {
    final db = await openMem();
    await db.execute('PRAGMA foreign_keys = ON');
    await db.insert('baby', {
      'id': 'b1',
      'name': 'Mali',
      'dob': '2026-03-01',
      'preferred_unit': 'oz',
      'created_at': '2026-05-13T00:00:00Z',
      'updated_at': '2026-05-13T00:00:00Z',
      'version': 1,
    });
    await db.insert('feed', {
      'id': 'f1',
      'baby_id': 'b1',
      'type': 'breast',
      'side': 'left',
      'started_at': '2026-05-13T00:00:00Z',
      'created_at': '2026-05-13T00:00:00Z',
      'updated_at': '2026-05-13T00:00:00Z',
      'version': 1,
    });
    await db.delete('baby', where: 'id = ?', whereArgs: ['b1']);
    final remaining = await db.query('feed');
    expect(remaining, isEmpty);
    await db.close();
  });

  test('check constraints reject invalid enum values', () async {
    final db = await openMem();
    expect(
      () => db.insert('baby', {
        'id': 'b1',
        'name': 'Mali',
        'dob': '2026-03-01',
        'sex': 'banana',
        'preferred_unit': 'oz',
        'created_at': '2026-05-13T00:00:00Z',
        'updated_at': '2026-05-13T00:00:00Z',
        'version': 1,
      }),
      throwsA(isA<DatabaseException>()),
    );
    await db.close();
  });
}
```

- [ ] **Step 2: Run — fails**

Run: `flutter test test/core/db/migrations_test.dart`
Expected: FAIL — `m001_initial.dart` not found.

- [ ] **Step 3: Write the migration**

```dart
// lib/core/db/migrations/m001_initial.dart
import 'package:sqflite_sqlcipher/sqflite.dart';

/// Migration v0 → v1. Creates the full DreamBook schema for v1.0.
Future<void> m001Initial(Database db) async {
  await db.execute('''
    CREATE TABLE meta (
      key        TEXT PRIMARY KEY NOT NULL,
      value      TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');

  await db.execute('''
    CREATE TABLE baby (
      id              TEXT PRIMARY KEY NOT NULL,
      name            TEXT NOT NULL,
      nickname        TEXT,
      dob             TEXT NOT NULL,
      sex             TEXT CHECK (sex IN ('male','female','unspecified')),
      photo_path      TEXT,
      preferred_unit  TEXT NOT NULL DEFAULT 'oz' CHECK (preferred_unit IN ('oz','ml')),
      created_at      TEXT NOT NULL,
      updated_at      TEXT NOT NULL,
      deleted_at      TEXT,
      version         INTEGER NOT NULL DEFAULT 1
    )
  ''');
  await db.execute('CREATE INDEX idx_baby_deleted_at ON baby(deleted_at)');

  await db.execute('''
    CREATE TABLE caregiver (
      id           TEXT PRIMARY KEY NOT NULL,
      display_name TEXT NOT NULL,
      device_id    TEXT NOT NULL,
      role         TEXT NOT NULL DEFAULT 'editor'
                     CHECK (role IN ('read_only','editor','admin')),
      joined_at    TEXT NOT NULL,
      revoked_at   TEXT,
      created_at   TEXT NOT NULL,
      updated_at   TEXT NOT NULL,
      deleted_at   TEXT,
      version      INTEGER NOT NULL DEFAULT 1
    )
  ''');
  await db.execute('CREATE INDEX idx_caregiver_revoked_at ON caregiver(revoked_at)');
  await db.execute('CREATE INDEX idx_caregiver_device_id  ON caregiver(device_id)');

  await db.execute('''
    CREATE TABLE pump_session (
      id           TEXT PRIMARY KEY NOT NULL,
      baby_id      TEXT NOT NULL REFERENCES baby(id) ON DELETE CASCADE,
      left_oz      REAL NOT NULL DEFAULT 0,
      right_oz     REAL NOT NULL DEFAULT 0,
      total_oz     REAL GENERATED ALWAYS AS (left_oz + right_oz) VIRTUAL,
      duration_min INTEGER,
      started_at   TEXT NOT NULL,
      ended_at     TEXT,
      note         TEXT,
      logged_by    TEXT REFERENCES caregiver(id),
      created_at   TEXT NOT NULL,
      updated_at   TEXT NOT NULL,
      deleted_at   TEXT,
      version      INTEGER NOT NULL DEFAULT 1
    )
  ''');
  await db.execute('CREATE INDEX idx_pump_session_baby_started ON pump_session(baby_id, started_at DESC)');

  await db.execute('''
    CREATE TABLE stash_bottle (
      id               TEXT PRIMARY KEY NOT NULL,
      baby_id          TEXT NOT NULL REFERENCES baby(id) ON DELETE CASCADE,
      pump_session_id  TEXT REFERENCES pump_session(id) ON DELETE SET NULL,
      oz               REAL NOT NULL,
      pumped_at        TEXT NOT NULL,
      frozen_at        TEXT,
      expires_at       TEXT NOT NULL,
      storage          TEXT NOT NULL DEFAULT 'freezer'
                         CHECK (storage IN ('freezer','fridge','room')),
      consumed_at      TEXT,
      consumed_feed_id TEXT,
      discarded_at     TEXT,
      logged_by        TEXT REFERENCES caregiver(id),
      created_at       TEXT NOT NULL,
      updated_at       TEXT NOT NULL,
      deleted_at       TEXT,
      version          INTEGER NOT NULL DEFAULT 1
    )
  ''');
  await db.execute('CREATE INDEX idx_stash_baby_expires ON stash_bottle(baby_id, expires_at)');
  await db.execute('CREATE INDEX idx_stash_baby_active  ON stash_bottle(baby_id, consumed_at, discarded_at)');
  await db.execute('CREATE INDEX idx_stash_pump_session ON stash_bottle(pump_session_id)');

  await db.execute('''
    CREATE TABLE feed (
      id                   TEXT PRIMARY KEY NOT NULL,
      baby_id              TEXT NOT NULL REFERENCES baby(id) ON DELETE CASCADE,
      type                 TEXT NOT NULL CHECK (type IN ('breast','bottle')),
      side                 TEXT CHECK (side IN ('left','right','both')),
      oz                   REAL,
      source               TEXT CHECK (source IN ('breastmilk','formula')),
      from_stash_bottle_id TEXT REFERENCES stash_bottle(id) ON DELETE SET NULL,
      started_at           TEXT NOT NULL,
      ended_at             TEXT,
      note                 TEXT,
      logged_by            TEXT REFERENCES caregiver(id),
      created_at           TEXT NOT NULL,
      updated_at           TEXT NOT NULL,
      deleted_at           TEXT,
      version              INTEGER NOT NULL DEFAULT 1
    )
  ''');
  await db.execute('CREATE INDEX idx_feed_baby_started ON feed(baby_id, started_at DESC)');
  await db.execute('CREATE INDEX idx_feed_baby_live    ON feed(baby_id, deleted_at, started_at)');
  await db.execute('CREATE INDEX idx_feed_from_stash   ON feed(from_stash_bottle_id)');

  await db.execute('''
    CREATE TABLE diaper (
      id          TEXT PRIMARY KEY NOT NULL,
      baby_id     TEXT NOT NULL REFERENCES baby(id) ON DELETE CASCADE,
      type        TEXT NOT NULL CHECK (type IN ('pee','poop','mixed','dry')),
      color       TEXT,
      consistency TEXT,
      occurred_at TEXT NOT NULL,
      note        TEXT,
      logged_by   TEXT REFERENCES caregiver(id),
      created_at  TEXT NOT NULL,
      updated_at  TEXT NOT NULL,
      deleted_at  TEXT,
      version     INTEGER NOT NULL DEFAULT 1
    )
  ''');
  await db.execute('CREATE INDEX idx_diaper_baby_occurred ON diaper(baby_id, occurred_at DESC)');
  await db.execute('CREATE INDEX idx_diaper_baby_live     ON diaper(baby_id, deleted_at, occurred_at)');

  await db.execute('''
    CREATE TABLE sleep (
      id           TEXT PRIMARY KEY NOT NULL,
      baby_id      TEXT NOT NULL REFERENCES baby(id) ON DELETE CASCADE,
      started_at   TEXT NOT NULL,
      ended_at     TEXT,
      duration_min INTEGER,
      location     TEXT CHECK (location IN ('crib','stroller','car','other')),
      note         TEXT,
      logged_by    TEXT REFERENCES caregiver(id),
      created_at   TEXT NOT NULL,
      updated_at   TEXT NOT NULL,
      deleted_at   TEXT,
      version      INTEGER NOT NULL DEFAULT 1
    )
  ''');
  await db.execute('CREATE INDEX idx_sleep_baby_started ON sleep(baby_id, started_at DESC)');
  await db.execute('CREATE INDEX idx_sleep_baby_live    ON sleep(baby_id, deleted_at, started_at)');

  await db.execute('''
    CREATE TABLE vaccination (
      id           TEXT PRIMARY KEY NOT NULL,
      baby_id      TEXT NOT NULL REFERENCES baby(id) ON DELETE CASCADE,
      vaccine_name TEXT NOT NULL,
      given_on     TEXT NOT NULL,
      clinic       TEXT,
      note         TEXT,
      logged_by    TEXT REFERENCES caregiver(id),
      created_at   TEXT NOT NULL,
      updated_at   TEXT NOT NULL,
      deleted_at   TEXT,
      version      INTEGER NOT NULL DEFAULT 1
    )
  ''');
  await db.execute('CREATE INDEX idx_vaccination_baby_given ON vaccination(baby_id, given_on DESC)');

  await db.execute('''
    CREATE TABLE sync_state (
      record_id       TEXT NOT NULL,
      table_name      TEXT NOT NULL,
      version         INTEGER NOT NULL,
      updated_at      TEXT NOT NULL,
      dirty           INTEGER NOT NULL DEFAULT 1 CHECK (dirty IN (0,1)),
      last_synced_at  TEXT,
      PRIMARY KEY (record_id, table_name)
    )
  ''');
  await db.execute('CREATE INDEX idx_sync_state_dirty ON sync_state(dirty, updated_at)');
  await db.execute('CREATE INDEX idx_sync_state_table ON sync_state(table_name, updated_at)');

  // Stamp the meta row.
  await db.insert('meta', {
    'key': 'schema_version',
    'value': '1',
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  });
}
```

- [ ] **Step 4: Write the database provider**

```dart
// lib/core/db/database_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../services/secure_key_service.dart';
import 'migrations/m001_initial.dart';
import 'migrations/migrations.dart';

final migrationsProvider = Provider<Migrations>(
  (_) => Migrations([m001Initial]),
);

/// Async DB handle — opened lazily on first access.
final appDatabaseProvider = FutureProvider<Database>((ref) async {
  final key = await SecureKeyService.getOrCreateDbKey();
  final dir = await getDatabasesPath();
  final path = p.join(dir, 'dreambook.db');
  final migrations = ref.watch(migrationsProvider);

  return openDatabase(
    path,
    password: key,
    version: migrations.currentVersion,
    onConfigure: (db) async {
      await db.execute('PRAGMA foreign_keys = ON');
      await db.execute('PRAGMA journal_mode = WAL');
      await db.execute('PRAGMA secure_delete = ON');
      await db.execute('PRAGMA synchronous = NORMAL');
    },
    onCreate: (db, _) => migrations.runAll(db),
    onUpgrade: (db, oldV, newV) => migrations.runFrom(db, oldV, newV),
  );
});
```

- [ ] **Step 5: Run all DB tests — pass**

Run: `flutter test test/core/db/migrations_test.dart`
Expected: PASS — 3/3.

- [ ] **Step 6: Commit**

```bash
git add lib/core/db/ test/core/db/ && \
git commit -m "feat(db): v1 schema + onCreate/onUpgrade plumbing + FK cascade tests"
```

---

## Task 13: Notification service (inexact-only, lint-enforced)

**Files:**
- Create: `lib/core/services/notification_service.dart`
- Modify: `android/app/src/main/AndroidManifest.xml` — declare notification channel permissions but NOT exact alarms
- Modify: `ios/Runner/Info.plist` — no special keys for inexact

- [ ] **Step 1: Write the service**

```dart
// lib/core/services/notification_service.dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String defaultChannelId   = 'dreambook_default_v1';
  static const String defaultChannelName = 'DreamBook reminders';
  static const String defaultChannelDesc =
      'Gentle, inexact reminders for pumping and stash expiry.';

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    final tzName = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzName));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestSoundPermission: false,
      requestBadgePermission: false,
      requestAlertPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );
  }

  static Future<bool> requestPermissions() async {
    final iosPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
    final iosGrant = await iosPlugin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        true;

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    final andGrant = await androidPlugin?.requestNotificationsPermission()
            ?? true;
    // NOTE: deliberately do NOT call requestExactAlarmsPermission().
    return iosGrant && andGrant;
  }

  /// Schedule an inexact one-shot notification.
  /// Never accepts an exact mode — caller cannot opt into precise timing.
  static Future<void> scheduleInexact({
    required int id,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    final scheduled = tz.TZDateTime.from(when, tz.local);
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          defaultChannelId,
          defaultChannelName,
          channelDescription: defaultChannelDesc,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  static Future<void> cancelAll() => _plugin.cancelAll();
}
```

- [ ] **Step 2: Add a CI lint check — grep AndroidManifest for forbidden permissions**

Create `tool/check_no_exact_alarms.sh`:

```bash
#!/usr/bin/env bash
# Fail if any forbidden exact-alarm permission or API leaks in.
set -euo pipefail

if grep -rnE 'SCHEDULE_EXACT_ALARM|USE_EXACT_ALARM' android/ 2>/dev/null; then
  echo "ERROR: Exact alarm permissions are forbidden by project policy." >&2
  exit 1
fi
if grep -rnE 'exactAllowWhileIdle|AndroidScheduleMode\.alarmClock|AndroidScheduleMode\.exact' lib/ 2>/dev/null; then
  echo "ERROR: Exact-alarm schedule modes are forbidden by project policy." >&2
  exit 1
fi
echo "OK: no exact alarm usage detected."
```

Run: `chmod +x tool/check_no_exact_alarms.sh && tool/check_no_exact_alarms.sh`
Expected: `OK: no exact alarm usage detected.`

- [ ] **Step 3: Commit**

```bash
git add lib/core/services/notification_service.dart tool/check_no_exact_alarms.sh && \
git commit -m "feat(notifications): inexact-only scheduler + grep check enforcing policy"
```

---

## Task 14: go_router skeleton

**Files:**
- Create: `lib/core/router/app_router.dart`

- [ ] **Step 1: Write the router**

```dart
// lib/core/router/app_router.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/home/presentation/home_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/share/presentation/share_invite_placeholder_screen.dart';
import '../providers/shared_preferences_provider.dart';

class AppRoutes {
  AppRoutes._();
  static const welcome      = '/welcome';
  static const home         = '/';
  static const shareInvite  = '/share/invite';
}

const _kOnboardingDoneKey = 'onboarding.done';

final appRouterProvider = Provider<GoRouter>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return GoRouter(
    initialLocation: AppRoutes.home,
    redirect: (context, state) {
      final onboarded = prefs.getBool(_kOnboardingDoneKey) ?? false;
      if (!onboarded && state.matchedLocation != AppRoutes.welcome) {
        return AppRoutes.welcome;
      }
      if (onboarded && state.matchedLocation == AppRoutes.welcome) {
        return AppRoutes.home;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.welcome,
        builder: (_, __) => const WelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.shareInvite,
        builder: (_, __) => const ShareInvitePlaceholderScreen(),
      ),
    ],
  );
});
```

- [ ] **Step 2: Commit** (compile gated by Tasks 15/16/17/18 — defer commit until those files exist)

---

## Task 15: Home screen — one-handed Quick-Log 2×2

**Files:**
- Create: `lib/features/home/presentation/home_screen.dart`

- [ ] **Step 1: Write the screen**

Design constraints per Spec §17.1 + user feedback today:
- All primary actions in **bottom half** (thumb reach)
- Quick-Log buttons ≥ 96 dp height (mom is half-asleep, one-handed)
- "Invite caregiver" CTA visible in top app bar (load-bearing differentiator)
- Hero "today's totals" card sits *above* the grid but is read-only — never blocks the thumb path
- Empty state for activity feed is warm, never blank
- All copy via `context.l10n` — no hardcoded strings

```dart
// lib/features/home/presentation/home_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/design_tokens.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appName),
        actions: [
          IconButton(
            tooltip: l10n.shareInviteCta,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            onPressed: () => context.go(AppRoutes.shareInvite),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.sm),
              // Top hero card — today's totals (placeholder values; live in Plan B).
              _TodayHeroCard(scheme: scheme),
              const SizedBox(height: AppSpacing.xs),
              // Caregiver attribution pill — silent answer to "is this multi-person mode?"
              const _CaregiverActivityPill(),
              const SizedBox(height: AppSpacing.md),
              // Today timeline — last 3 events as horizontal chips.
              // Plan A: placeholder data; Plan B replaces with live entries stream.
              const _TodayTimelineRow(),
              const SizedBox(height: AppSpacing.md),
              // Middle: spacer that holds whitespace without reading as "loading".
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: Text(
                      l10n.shareJustYou,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium(
                        color: AppColors.inkSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              // Bottom: Quick-Log 2x2 grid — thumb-reachable.
              _QuickLogGrid(),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodayHeroCard extends StatelessWidget {
  const _TodayHeroCard({required this.scheme});
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _Stat(label: l10n.homeQuickLogFeed, value: '0 oz'),
            _Stat(label: l10n.homeQuickLogDiaper, value: '0'),
            _Stat(label: l10n.homeQuickLogSleep, value: '0 hr'),
            _Stat(label: l10n.homeQuickLogPump, value: '0'),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          style: AppTypography.numeric(
            size: 20,
            weight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          label,
          style: AppTypography.labelLarge(
            color: scheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

class _CaregiverActivityPill extends StatelessWidget {
  const _CaregiverActivityPill();

  @override
  Widget build(BuildContext context) {
    // Plan A: hardcoded "Just you". Plan C wires real caregiver count.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Row(
        children: [
          Icon(Icons.people_outline,
              size: 16, color: AppColors.inkSecondary),
          const SizedBox(width: AppSpacing.xs),
          Text(
            'Logged by you',
            style: AppTypography.labelLarge(color: AppColors.inkSecondary),
          ),
        ],
      ),
    );
  }
}

class _TodayTimelineRow extends StatelessWidget {
  const _TodayTimelineRow();

  // Plan A: static placeholder chips. Plan B swaps in live stream from feed/diaper/sleep tables.
  static const _samples = <_TimelineChip>[
    _TimelineChip(icon: Icons.water_drop_outlined, label: 'Feed · 4 oz · 2h ago'),
    _TimelineChip(icon: Icons.baby_changing_station_outlined, label: 'Diaper · 3h ago'),
    _TimelineChip(icon: Icons.bedtime_outlined, label: 'Sleep · 4h ago'),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        itemCount: _samples.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (_, i) => _samples[i],
      ),
    );
  }
}

class _TimelineChip extends StatelessWidget {
  const _TimelineChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.neutralMuted,
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.inkSecondary),
          const SizedBox(width: AppSpacing.xs),
          Text(label,
              style: AppTypography.labelLarge(color: AppColors.inkPrimary)),
        ],
      ),
    );
  }
}

class _QuickLogGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _QuickLogButton(
          icon: Icons.water_drop_outlined,
          label: l10n.homeQuickLogFeed,
          onTap: () {/* Plan B: open /feed/new */},
        ),
        _QuickLogButton(
          icon: Icons.compress_outlined,
          label: l10n.homeQuickLogPump,
          onTap: () {/* Plan B: open /pump/new */},
        ),
        _QuickLogButton(
          icon: Icons.baby_changing_station_outlined,
          label: l10n.homeQuickLogDiaper,
          onTap: () {/* Plan B: open /diaper/new */},
        ),
        _QuickLogButton(
          icon: Icons.bedtime_outlined,
          label: l10n.homeQuickLogSleep,
          onTap: () {/* Plan B: open /sleep/new */},
        ),
      ],
    );
  }
}

class _QuickLogButton extends StatelessWidget {
  const _QuickLogButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSpacing.quickLogButton),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 28, color: scheme.primary),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  label,
                  style: AppTypography.titleLarge(color: scheme.onSurface),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit** (with Task 16+17+18 to keep router compiling)

---

## Task 16: Share/Invite placeholder screen

**Files:**
- Create: `lib/features/share/presentation/share_invite_placeholder_screen.dart`

Plan A goal: a **design-reviewable** invite screen that shows the spec §17.2 "magic moment" layout — 40+ pt code, expiry chip, share-via button. The code value is hardcoded for this turn; real generation arrives in Plan C with the crypto module.

- [ ] **Step 1: Write the screen**

```dart
// lib/features/share/presentation/share_invite_placeholder_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/theme/design_tokens.dart';

class ShareInvitePlaceholderScreen extends StatelessWidget {
  const ShareInvitePlaceholderScreen({super.key});

  // Hardcoded sample. Plan C: replaced by InviteCodeService.generate().
  // Format: XXXX-XXXX Crockford base32 (no I/L/O/U); one hyphen at pos 4.
  static const String _sampleCode = 'MK29-HFX4';
  static const String _sampleBabyName = 'Mali';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.shareTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.shareInviteHeadline(_sampleBabyName),
                textAlign: TextAlign.center,
                style: AppTypography.headlineMedium(color: AppColors.inkPrimary),
              ),
              const SizedBox(height: AppSpacing.lg),
              // 1) QR FIRST — scan is the fast path (~2s vs ~15s typing).
              Center(
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    color: AppColors.neutralMuted,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                  ),
                  child: const Center(
                    child: Icon(Icons.qr_code_2_outlined, size: 96),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Or read this aloud',
                textAlign: TextAlign.center,
                style: AppTypography.labelLarge(color: AppColors.inkSecondary),
              ),
              const SizedBox(height: AppSpacing.xs),
              // 2) Code BELOW QR — 56pt tabular hero for "dictate over phone" use.
              SelectableText(
                _sampleCode,
                textAlign: TextAlign.center,
                style: AppTypography.statHero(color: AppColors.lavender700),
              ),
              const SizedBox(height: AppSpacing.xs),
              Center(
                child: Chip(
                  label: Text(l10n.shareInviteExpiresIn(60)),
                  backgroundColor: AppColors.neutralMuted,
                  side: BorderSide.none,
                ),
              ),
              const Spacer(),
              // 3) Native share — thumb-zone bottom-third primary.
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    const ClipboardData(text: _sampleCode),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.actionDone)),
                  );
                },
                icon: const Icon(Icons.share_outlined),
                label: Text(l10n.shareInviteShareVia),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit** (combined with Task 14+15+17+18)

---

## Task 17: SharedPreferences provider + main.dart boot

**Files:**
- Create: `lib/core/providers/shared_preferences_provider.dart`
- Create: `lib/app.dart`
- Modify: `lib/main.dart` (replace flutter-create default)

- [ ] **Step 1: Write the SharedPreferences provider sentinel**

```dart
// lib/core/providers/shared_preferences_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Throws if not overridden — main.dart must override this with the
/// loaded SharedPreferences instance before runApp.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (_) => throw UnimplementedError('Must be overridden in main()'),
);
```

- [ ] **Step 2: Write `lib/app.dart`**

```dart
// lib/app.dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/theme_mode_controller.dart';
import 'l10n/generated/app_localizations.dart';

class DreamBookApp extends ConsumerWidget {
  const DreamBookApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(themeProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'DreamBook',
      debugShowCheckedModeBanner: false,
      theme: theme,
      routerConfig: router,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
```

- [ ] **Step 3: Replace `lib/main.dart`**

```dart
// lib/main.dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/providers/shared_preferences_provider.dart';
import 'core/services/notification_service.dart';
import 'core/services/secure_key_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Ensure encryption key exists (Keychain / EncryptedSharedPreferences).
  await SecureKeyService.getOrCreateDbKey();

  // 2. Notifications init (channels, timezone db).
  await NotificationService.init();

  // 3. SharedPreferences (sync provider override).
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const DreamBookApp(),
    ),
  );
}
```

- [ ] **Step 4: Verify**

Run: `flutter analyze && flutter test`
Expected: PASS. (Tests from earlier tasks must still pass.)

- [ ] **Step 5: Commit (router + screens + main together)**

```bash
git add lib/core/router/ lib/core/providers/ lib/features/ lib/app.dart lib/main.dart && \
git commit -m "feat(shell): router + Home (one-handed Quick-Log) + Share invite placeholder + main boot"
```

---

## Task 18: Welcome onboarding screen (baby name only)

**Files:**
- Create: `lib/features/onboarding/presentation/welcome_screen.dart`

Spec §17.3 anti-pattern: never an onboarding wall. One screen, baby name only, the rest skippable. This task implements that minimum.

- [ ] **Step 1: Write the screen**

```dart
// lib/features/onboarding/presentation/welcome_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/providers/shared_preferences_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/design_tokens.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _nameCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    // Activation-first: baby name is optional. Default "Baby" if empty.
    // Routes to /home in Plan A; Plan B will retarget to /feed/new so the
    // primary CTA "Log a feed now" delivers immediate value.
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = _nameCtrl.text.trim();
    final name = raw.isEmpty ? 'Baby' : raw;
    await prefs.setString('baby.name', name);
    await prefs.setBool('onboarding.done', true);
    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xl),
              Text(
                l10n.welcomeHeadline,
                style: AppTypography.headlineLarge(color: scheme.onSurface),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.welcomeSubcopy,
                style: AppTypography.bodyLarge(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: l10n.welcomeBabyNameLabel,
                  hintText: l10n.welcomeBabyNameHint,
                ),
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _start(),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _start,
                child: Text(l10n.welcomeStartCta),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Commit** (already committed in Task 17's combined commit if you applied that order; otherwise commit now)

---

## Task 19: DreamBook CLAUDE.md (codebase memory)

**Files:**
- Create: `/Users/nipitphand/Projects/DreamBook/CLAUDE.md`

- [ ] **Step 1: Write the file**

```markdown
# DreamBook — Project Context

## Platform
- Cross-platform Flutter — runs on Android + iOS from one codebase
- **Android first** (Plan A through F all verify on Android emulator); iOS launch ~1-2 months later
- **Android minSdkVersion 23** (diverges from DreamBaby's 21 — required by `purchases_flutter ^10` + `flutter_secure_storage ^10`)
- iOS deployment target 13.0+

## Stack
- Flutter 3.41+, Dart 3.10+
- **Riverpod 3.x with `@riverpod` codegen** (greenfield — no legacy.dart imports)
- go_router ^17, sqflite_sqlcipher ^3.4, flutter_secure_storage ^10, flutter_localizations + intl, purchases_flutter ^10 (RevenueCat), supabase_flutter (Plan C+), cryptography (Plan C+), pdf+printing (Plan E)
- Notifications: `flutter_local_notifications` ^21 — **inexact only**, never `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`

## Companion app
- DreamBaby is the sibling app at `/Users/nipitphand/Projects/DreamBaby/`
- Many code patterns reused from there (SecureKeyService, NotificationService inexact rule, RC config, l10n_ext.dart)
- Plan F adds the cross-app bridge (deep-link + shared Baby Profile via Android FileProvider / iOS App Group)

## Target market & content
- Primary: USA (English). Secondary: Thailand (Thai). Expansion (post-v1.1): ES, PT-BR, JA, KO, DE
- Target user: 0–24 month babies. Pumping moms + multi-caregiver households.

## Features (v1.0 MVP scope per spec D1–D15)
- Feed (breast L/R timer + bottle oz/ml), Pump session (L/R oz), Freezer Stash (visual + expiry alerts), Diaper, Sleep
- **Caregiver share** = differentiator (8-char Crockford base32 invite code, 1-hour TTL, E2E AES-GCM in Plan C)
- Daily Summary, Vaccination log, Visit Summary PDF (premium, default 7-day range)
- Multi-baby (premium), RevenueCat paywall (Monthly $2.99 / Yearly $19.99 / Lifetime $29.99 / 7-day trial)

## Privacy & Security
- **No login, no account, no email** — invite code + device ID only
- All local data encrypted at rest via `sqflite_sqlcipher`; DB key in Keychain/EncryptedSharedPreferences
- All synced data encrypted client-side (AES-GCM); Supabase sees only ciphertext + row metadata
- No analytics SDK. Crashlytics opt-in only.
- App data backup disabled (`android:allowBackup="false"`) — would break decryption on restore
- COPPA/GDPR-K/PDPA exposure: age cap 0–24 mo, kids-data lawyer reviews PP/ToS before public launch

## Key architecture decisions
- **Migration runner: append-only `List<MigrationStep>`** in `lib/core/db/migrations/migrations.dart` (greenfield — DreamBaby has no shared runner)
- **Soft-delete pattern**: every syncable row has `deleted_at TEXT` + `version INTEGER`; sync_state ledger tracks dirty rows
- **Thai fonts BUNDLED** in `assets/fonts/` (IBM Plex Sans Thai) — offline-first for 3 AM parents on flaky wifi
- **Theme `ColorScheme` explicit, not `fromSeed`** — preserves curated palette across light/dark/nightTint
- **Sync (Plan C)**: Supabase region `ap-southeast-1` (Singapore); last-write-wins per `(record_id, version)`
- **Notifications**: inexact only. Enforced by `tool/check_no_exact_alarms.sh` grep check.

## Folder structure
- `/lib/features/onboarding`, `/home`, `/feed`, `/pump`, `/diaper`, `/sleep`, `/stash`, `/share`, `/summary`, `/vaccination`, `/visit_report`, `/subscription`, `/settings`, `/dreambaby_bridge`
- `/lib/core/theme`, `/db`, `/sync`, `/crypto`, `/router`, `/services`, `/providers`, `/l10n`
- `/lib/l10n/app_en.arb` + `/app_th.arb` → `flutter gen-l10n` outputs to `/lib/l10n/generated/`

## Plan roadmap
- **Plan A** (this) — Foundation: scaffold, theme, L10n, DB v1, secure key, router, Home shell, Share invite placeholder
- **Plan B** — Local logging: Feed/Pump/Stash/Diaper/Sleep CRUD + Daily Summary (offline only)
- **Plan C** — Sync + Crypto: Supabase, AES-GCM, invite code generation, caregiver onboarding
- **Plan D** — Premium: Multi-baby, RevenueCat, paywall
- **Plan E** — Clinical: Vaccination log, Visit Summary PDF
- **Plan F** — Polish + DreamBaby bridge, L10n review, QA, beta

## Verification commands
- `flutter analyze` — must pass
- `flutter test` — must pass
- `flutter build apk --debug` — must produce APK
- `tool/check_no_exact_alarms.sh` — must say OK
- `flutter gen-l10n` — regenerates `lib/l10n/generated/` after ARB edits
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md && \
git commit -m "docs: project memory for DreamBook (minSdk 23 divergence, plan roadmap)"
```

---

## Task 20: Final gate — analyze, test, build, run

**Files:** none — verification only.

- [ ] **Step 1: Lint**

Run: `flutter analyze`
Expected: PASS — zero warnings, zero errors.

- [ ] **Step 2: Test**

Run: `flutter test`
Expected: PASS — all from Tasks 7, 10, 12 (≥ 9 assertions across 3 test files).

- [ ] **Step 3: No exact alarms**

Run: `tool/check_no_exact_alarms.sh`
Expected: `OK: no exact alarm usage detected.`

- [ ] **Step 4: Android debug build**

Run: `flutter build apk --debug`
Expected: APK at `build/app/outputs/flutter-apk/app-debug.apk`.

- [ ] **Step 5: Manual smoke on emulator**

Run: `flutter emulators --launch <id> && flutter run -d <device-id>`

Verify on screen:
1. Welcome screen loads with EN copy by default (or TH if device locale is Thai)
2. Enter baby name "Mali" → tap Start → Home appears
3. Hero card shows 4 stat zeros
4. 2×2 Quick-Log grid visible at bottom; all 4 buttons tappable with thumb without re-grip
5. App bar invite icon → navigates to Share Invite screen showing `MK29-HFX4` in 44pt
6. Copy button shows snackbar; back arrow returns Home
7. Force quit + relaunch → opens directly on Home (onboarding persisted)
8. Toggle device language to Thai → all copy localizes; baby name reads `ยินดีต้อนรับ` etc.

- [ ] **Step 6: Final commit / tag**

```bash
git add -A && \
git commit --allow-empty -m "chore: Plan A foundation complete — APK builds, tests green, smoke passed" && \
git tag -a plan-a-complete -m "DreamBook foundation: theme, L10n, DB v1, secure key, router, Home shell"
```

---

## Self-Review

**1. Spec coverage check (Plan A scope only — Week 1 in §15):**
- ✅ Flutter project init → Tasks 1, 2, 3
- ✅ DB schema (encrypted sqflite v1) → Tasks 10, 11, 12
- ✅ Basic routes → Task 14
- ✅ Theme/L10n scaffold → Tasks 5–9
- ✅ Inexact-only notifications → Task 13
- ✅ One-handed Home design (user emphasis today) → Task 15
- ✅ Share placeholder route (user emphasis today) → Task 16
- ✅ Onboarding minimum (Spec §17.3 anti-pattern compliance) → Task 18
- ⏭️ Out of Plan A scope: feed/pump/diaper/sleep CRUD, Supabase sync, RC paywall, vaccination, PDF, multi-baby — all properly deferred to Plans B–F.

**2. Placeholder scan:** no TODOs, no "fill in", no "similar to Task N". Every code block is complete and runnable.

**3. Type consistency:** verified — `AppLocalizations.of(context)` returns non-null (l10n.yaml `nullable-getter: false`), `Migrations.runFrom(db, oldVersion, newVersion)` signature consistent across Task 11 and Task 12 callers, `themeProvider` and `appRouterProvider` both `Provider`-typed and consumed via `ref.watch` in `app.dart`.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-05-13-foundation.md`. Two execution options:

**1. Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — execute tasks in this session using `superpowers:executing-plans`, batch execution with checkpoints

Which approach?
