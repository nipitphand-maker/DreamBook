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
