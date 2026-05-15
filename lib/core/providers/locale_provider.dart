import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _kLocaleKey = 'settings.locale';

class LocaleNotifier extends Notifier<Locale?> {
  @override
  Locale? build() {
    final code = ref.read(sharedPreferencesProvider).getString(_kLocaleKey);
    return code == null ? null : Locale(code);
  }

  Future<void> setLocale(Locale? locale) async {
    final prefs = ref.read(sharedPreferencesProvider);
    if (locale == null) {
      await prefs.remove(_kLocaleKey);
    } else {
      await prefs.setString(_kLocaleKey, locale.languageCode);
    }
    state = locale;
  }
}

final localeProvider =
    NotifierProvider<LocaleNotifier, Locale?>(LocaleNotifier.new);
