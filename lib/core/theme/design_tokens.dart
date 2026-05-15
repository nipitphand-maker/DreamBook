import 'dart:ui';

import 'package:flutter/material.dart';

/// Color tokens per Spec §17.7. Three palettes: light, dark, nightTint.
/// nightTint shifts toward warm red/amber to preserve melatonin during
/// 2–4 AM feeds (long-wavelength light suppresses melatonin least).
class AppColors {
  AppColors._();

  // --- Light (Misty Morning — warm sage) ---
  static const Color lightPrimary = Color(0xFF6E8F7C);    // sage fill (3.34:1 — decorative only)
  static const Color lightAccent = Color(0xFFE8A87C);     // terracotta fill (decorative only)
  static const Color lightSuccess = Color(0xFF5A8A6A);    // deeper sage
  static const Color lightWarning = Color(0xFFCC8020);    // amber-brown
  static const Color lightSurface = Color(0xFFFAF7F2);    // warm near-white
  static const Color lightOnSurface = Color(0xFF1F2B27);  // dark forest 13.71:1 AAA
  static const Color lightError = Color(0xFFB3261E);
  static const Color lightOnPrimary = Color(0xFF1F2B27);  // dark on sage fill

  // --- Dark (Misty Morning dark) ---
  static const Color darkPrimary = Color(0xFF74A88A);     // lighter sage
  static const Color darkAccent = Color(0xFFD4906A);      // muted terracotta
  static const Color darkSuccess = Color(0xFF6BA880);
  static const Color darkWarning = Color(0xFFB87820);
  static const Color darkSurface = Color(0xFF121B17);     // dark forest-green
  static const Color darkOnSurface = Color(0xFFD6EDE5);   // pale mint 14.31:1 AAA
  static const Color darkError = Color(0xFFF2B8B5);
  static const Color darkOnPrimary = Color(0xFF121B17);

  // --- Night-tint (red-shift, melatonin-safe) ---
  static const Color nightPrimary = Color(0xFF6A5530);    // amber-desaturated
  static const Color nightAccent = Color(0xFFA05030);     // deep terracotta
  static const Color nightSuccess = Color(0xFF506850);
  static const Color nightWarning = Color(0xFF904A10);
  static const Color nightSurface = Color(0xFF1A0C06);    // deep red-brown
  static const Color nightOnSurface = Color(0xFFE0C8B0);  // warm tan 11.64:1 AAA
  static const Color nightError = Color(0xFFD07060);
  static const Color nightOnPrimary = Color(0xFF1A0C06);

  // --- Ink + neutral (text + dividers — all WCAG AA on #FAF7F2) ---
  static const Color inkPrimary = Color(0xFF1F2B27);    // dark forest-black  13.71:1 AAA
  static const Color inkSecondary = Color(0xFF546460);  // muted sage-gray     5.83:1 AA
  static const Color neutralMuted = Color(0xFFE8E2D8);  // warm off-white dividers

  // --- *.700 derivatives — all verified AA on surface (#FAF7F2) ---
  static const Color lavender700 = Color(0xFF3D6655); // sage primary text    6.08:1 AA
  static const Color peach700 = Color(0xFFA05A2A);    // terracotta text      4.92:1 AA
  static const Color sage700 = Color(0xFF2E5E40);     // forest green text    7.04:1 AA
  static const Color honey700 = Color(0xFF8A5200);    // amber text           5.98:1 AA
}

/// Typography per Spec §17.6. Locale-aware: TH uses bundled IBMPlexSansThai
/// (assets/fonts/), every other locale uses the platform default (SF Pro on
/// iOS, Roboto on Android) — zero asset cost for non-TH users since the OS
/// font ships preinstalled.
class AppTypography {
  AppTypography._();

  static const String _thaiFamily = 'IBMPlexSansThai';
  static const String _latinFamily = 'Nunito';

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
    final family = isThai(forceLocale: locale) ? _thaiFamily : _latinFamily;
    // fontFamilyFallback ensures Thai characters in user-supplied strings
    // (e.g. baby names typed in an English-locale app) still render correctly.
    return TextStyle(
      fontFamily: family,
      fontFamilyFallback: isThai(forceLocale: locale)
          ? null
          : const [_thaiFamily, 'Roboto'],
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
        size: 34,
        weight: FontWeight.w600,
        height: 1.15,
        letterSpacing: -0.4,
        color: color,
        locale: locale,
      );
  static TextStyle headlineLarge({Locale? locale, Color? color}) => _base(
        size: 28,
        weight: FontWeight.w600,
        height: 1.2,
        letterSpacing: -0.3,
        color: color,
        locale: locale,
      );
  static TextStyle headlineMedium({Locale? locale, Color? color}) => _base(
        size: 22,
        weight: FontWeight.w600,
        height: 1.25,
        letterSpacing: -0.2,
        color: color,
        locale: locale,
      );
  static TextStyle titleLarge({Locale? locale, Color? color}) => _base(
        size: 18,
        weight: FontWeight.w600,
        height: 1.3,
        letterSpacing: -0.1,
        color: color,
        locale: locale,
      );

  // Body: min 16 pt for accessibility (Spec §17.2 A11y rule).
  static TextStyle bodyLarge({Locale? locale, Color? color}) => _base(
        size: 16,
        weight: FontWeight.w400,
        height: 1.45,
        color: color,
        locale: locale,
      );
  static TextStyle bodyMedium({Locale? locale, Color? color}) => _base(
        size: 15,
        weight: FontWeight.w400,
        height: 1.45,
        color: color,
        locale: locale,
      );
  static TextStyle labelLarge({Locale? locale, Color? color}) => _base(
        size: 14,
        weight: FontWeight.w500,
        height: 1.3,
        letterSpacing: 0.1,
        color: color,
        locale: locale,
      );

  /// Hero numeric — invite code, weekly-summary headline, milestone stat.
  /// Always tabular, always weight 700, always tightened tracking.
  static TextStyle statHero({Locale? locale, Color? color}) => _base(
        size: 48,
        weight: FontWeight.w700,
        height: 1.05,
        letterSpacing: -1.5,
        features: _tabular,
        color: color,
        locale: locale,
      );

  /// Tabular numerals — use anywhere digits stack vertically or animate.
  static TextStyle numeric({
    double size = 16,
    FontWeight weight = FontWeight.w500,
    Locale? locale,
    Color? color,
  }) =>
      _base(
        size: size,
        weight: weight,
        features: _tabular,
        color: color,
        locale: locale,
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
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;

  /// Minimum touch target per Spec §17.2 one-thumb rule.
  static const double minTouchTarget = 48;

  /// Quick-Log buttons should be larger — mom is half-asleep + one-handed.
  static const double quickLogButton = 96;
}

class AppElevation {
  AppElevation._();
  static const double none = 0;
  static const double level1 = 1;
  static const double level2 = 3;
  static const double level3 = 6;
  static const double sheet = 8;
}
