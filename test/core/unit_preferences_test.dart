import 'package:dreambook/core/services/unit_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UnitPreferences.fromLocale', () {
    test('en → oz, lbOz, inches, fahrenheit, h12, sunday', () {
      final prefs = UnitPreferences.fromLocale('en');
      expect(prefs.volume, VolumeUnit.oz);
      expect(prefs.weight, WeightUnit.lbOz);
      expect(prefs.length, LengthUnit.inches);
      expect(prefs.temp, TempUnit.fahrenheit);
      expect(prefs.timeFormat, TimeFormat.h12);
      expect(prefs.weekStart, WeekStart.sunday);
    });

    test('th → ml, kg, cm, celsius, h24, monday', () {
      final prefs = UnitPreferences.fromLocale('th');
      expect(prefs.volume, VolumeUnit.ml);
      expect(prefs.weight, WeightUnit.kg);
      expect(prefs.length, LengthUnit.cm);
      expect(prefs.temp, TempUnit.celsius);
      expect(prefs.timeFormat, TimeFormat.h24);
      expect(prefs.weekStart, WeekStart.monday);
    });

    test('de → ml, kg, cm, celsius, h24, sunday', () {
      final prefs = UnitPreferences.fromLocale('de');
      expect(prefs.volume, VolumeUnit.ml);
      expect(prefs.weight, WeightUnit.kg);
      expect(prefs.length, LengthUnit.cm);
      expect(prefs.temp, TempUnit.celsius);
      expect(prefs.timeFormat, TimeFormat.h24);
      expect(prefs.weekStart, WeekStart.sunday);
    });
  });

  group('UnitConverter.displayVolume', () {
    test('295.735 ml → oz ≈ 10.0', () {
      final (value, label) = UnitConverter.displayVolume(295.735, VolumeUnit.oz);
      expect(label, 'oz');
      expect(value, closeTo(10.0, 0.05));
    });

    test('100.0 ml → ml = 100.0', () {
      final (value, label) = UnitConverter.displayVolume(100.0, VolumeUnit.ml);
      expect(label, 'ml');
      expect(value, 100.0);
    });
  });

  group('UnitConverter.displayWeight', () {
    test('3400 g → lbOz contains "lb" and "oz"', () {
      final (formatted, label) =
          UnitConverter.displayWeight(3400.0, WeightUnit.lbOz);
      expect(formatted, contains('lb'));
      expect(formatted, contains('oz'));
      expect(label, '');
    });

    test('3400 g → kg = 3.4', () {
      final (formatted, label) =
          UnitConverter.displayWeight(3400.0, WeightUnit.kg);
      expect(double.parse(formatted), closeTo(3.4, 0.01));
      expect(label, 'kg');
    });
  });

  group('UnitConverter.displayLength', () {
    test('50.8 cm → inches ≈ 20.0', () {
      final (value, label) = UnitConverter.displayLength(50.8, LengthUnit.inches);
      expect(label, 'in');
      expect(value, closeTo(20.0, 0.05));
    });
  });

  group('UnitConverter.displayTemp', () {
    test('37.0°C → °F ≈ 98.6', () {
      final (value, label) = UnitConverter.displayTemp(37.0, TempUnit.fahrenheit);
      expect(label, '°F');
      expect(value, closeTo(98.6, 0.05));
    });
  });
}
