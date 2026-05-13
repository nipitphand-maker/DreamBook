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
        displayLarge: AppTypography.displayLarge(color: scheme.onSurface),
        headlineLarge: AppTypography.headlineLarge(color: scheme.onSurface),
        headlineMedium: AppTypography.headlineMedium(color: scheme.onSurface),
        titleLarge: AppTypography.titleLarge(color: scheme.onSurface),
        bodyLarge: AppTypography.bodyLarge(color: scheme.onSurface),
        bodyMedium: AppTypography.bodyMedium(color: scheme.onSurface),
        labelLarge: AppTypography.labelLarge(color: scheme.onSurface),
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
