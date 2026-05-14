import 'dart:io';

import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/core/services/unit_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// SharedPreferences keys
const _kVolume = 'settings.unit.volume'; // 'oz' | 'ml'
const _kWeight = 'settings.unit.weight'; // 'lb_oz' | 'kg'
const _kLength = 'settings.unit.length'; // 'in' | 'cm'
const _kTemp = 'settings.unit.temp'; // 'f' | 'c'
const _kTimeFormat = 'settings.unit.time'; // '12h' | '24h'
const _kWeekStart = 'settings.unit.week'; // 'sun' | 'mon'

class UnitPreferencesNotifier extends Notifier<UnitPreferences> {
  @override
  UnitPreferences build() {
    final prefs = ref.watch(sharedPreferencesProvider);

    // Determine defaults from locale if keys are absent
    final languageCode = Platform.localeName.split('_').first;
    final defaults = UnitPreferences.fromLocale(languageCode);

    final volumeRaw = prefs.getString(_kVolume);
    final weightRaw = prefs.getString(_kWeight);
    final lengthRaw = prefs.getString(_kLength);
    final tempRaw = prefs.getString(_kTemp);
    final timeRaw = prefs.getString(_kTimeFormat);
    final weekRaw = prefs.getString(_kWeekStart);

    return UnitPreferences(
      volume: volumeRaw == null
          ? defaults.volume
          : (volumeRaw == 'oz' ? VolumeUnit.oz : VolumeUnit.ml),
      weight: weightRaw == null
          ? defaults.weight
          : (weightRaw == 'lb_oz' ? WeightUnit.lbOz : WeightUnit.kg),
      length: lengthRaw == null
          ? defaults.length
          : (lengthRaw == 'in' ? LengthUnit.inches : LengthUnit.cm),
      temp: tempRaw == null
          ? defaults.temp
          : (tempRaw == 'f' ? TempUnit.fahrenheit : TempUnit.celsius),
      timeFormat: timeRaw == null
          ? defaults.timeFormat
          : (timeRaw == '12h' ? TimeFormat.h12 : TimeFormat.h24),
      weekStart: weekRaw == null
          ? defaults.weekStart
          : (weekRaw == 'sun' ? WeekStart.sunday : WeekStart.monday),
    );
  }

  void setVolume(VolumeUnit v) {
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setString(_kVolume, v == VolumeUnit.oz ? 'oz' : 'ml');
    state = state.copyWith(volume: v);
  }

  void setWeight(WeightUnit w) {
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setString(_kWeight, w == WeightUnit.lbOz ? 'lb_oz' : 'kg');
    state = state.copyWith(weight: w);
  }

  void setLength(LengthUnit l) {
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setString(_kLength, l == LengthUnit.inches ? 'in' : 'cm');
    state = state.copyWith(length: l);
  }

  void setTemp(TempUnit t) {
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setString(_kTemp, t == TempUnit.fahrenheit ? 'f' : 'c');
    state = state.copyWith(temp: t);
  }

  void setTimeFormat(TimeFormat f) {
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setString(_kTimeFormat, f == TimeFormat.h12 ? '12h' : '24h');
    state = state.copyWith(timeFormat: f);
  }

  void setWeekStart(WeekStart w) {
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setString(_kWeekStart, w == WeekStart.sunday ? 'sun' : 'mon');
    state = state.copyWith(weekStart: w);
  }
}

final unitPreferencesProvider =
    NotifierProvider<UnitPreferencesNotifier, UnitPreferences>(
  UnitPreferencesNotifier.new,
);
