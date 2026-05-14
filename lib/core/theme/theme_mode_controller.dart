import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/shared_preferences_provider.dart';
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
    choice: UserThemeChoice.light,
    redTintPreserveMelatonin: false,
  );
}

const _kThemeModeKey = 'theme.mode';
const _kRedTintKey = 'theme.redTint';

class ThemeModeController extends AsyncNotifier<ThemeModeState> {
  @override
  Future<ThemeModeState> build() async {
    // sharedPreferencesProvider is pre-initialised in main() before runApp,
    // so ref.read is synchronous — no await needed.
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = prefs.getString(_kThemeModeKey) ?? _encode(ThemeModeState.initial.choice);
    final redTint = prefs.getBool(_kRedTintKey) ?? false;
    return ThemeModeState(
      choice: _decode(raw),
      redTintPreserveMelatonin: redTint,
    );
  }

  Future<void> setChoice(UserThemeChoice choice) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_kThemeModeKey, _encode(choice));
    state = AsyncData(
      (state.value ?? ThemeModeState.initial).copyWith(choice: choice),
    );
  }

  Future<void> toggleRedTint(bool enabled) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_kRedTintKey, enabled);
    state = AsyncData(
      (state.value ?? ThemeModeState.initial)
          .copyWith(redTintPreserveMelatonin: enabled),
    );
  }

  static String _encode(UserThemeChoice c) => switch (c) {
        UserThemeChoice.system => 'system',
        UserThemeChoice.light => 'light',
        UserThemeChoice.dark => 'dark',
        UserThemeChoice.nightTint => 'nightTint',
      };

  static UserThemeChoice _decode(String s) => switch (s) {
        'light' => UserThemeChoice.light,
        'dark' => UserThemeChoice.dark,
        'nightTint' => UserThemeChoice.nightTint,
        _ => UserThemeChoice.system,
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
