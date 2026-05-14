// Unit preferences — pure Dart, no Riverpod.
// Canonical input for all conversion helpers is ALWAYS the SI/metric unit
// (ml, grams, cm, °C). Output is whatever the user's preference requests.

enum VolumeUnit { oz, ml }

enum WeightUnit { lbOz, kg }

enum LengthUnit { inches, cm }

enum TempUnit { fahrenheit, celsius }

enum TimeFormat { h12, h24 }

enum WeekStart { sunday, monday }

class UnitPreferences {
  const UnitPreferences({
    required this.volume,
    required this.weight,
    required this.length,
    required this.temp,
    required this.timeFormat,
    required this.weekStart,
  });

  final VolumeUnit volume;
  final WeightUnit weight;
  final LengthUnit length;
  final TempUnit temp;
  final TimeFormat timeFormat;
  final WeekStart weekStart;

  /// Locale-aware defaults:
  /// - US ('en_US', 'en') → oz, lbOz, inches, fahrenheit, h12, sunday
  /// - TH ('th')          → ml, kg, cm, celsius, h24, monday
  /// - all others         → ml, kg, cm, celsius, h24, sunday
  factory UnitPreferences.fromLocale(String languageCode) {
    final code = languageCode.toLowerCase();
    if (code == 'en') {
      return const UnitPreferences(
        volume: VolumeUnit.oz,
        weight: WeightUnit.lbOz,
        length: LengthUnit.inches,
        temp: TempUnit.fahrenheit,
        timeFormat: TimeFormat.h12,
        weekStart: WeekStart.sunday,
      );
    }
    if (code == 'th') {
      return const UnitPreferences(
        volume: VolumeUnit.ml,
        weight: WeightUnit.kg,
        length: LengthUnit.cm,
        temp: TempUnit.celsius,
        timeFormat: TimeFormat.h24,
        weekStart: WeekStart.monday,
      );
    }
    // All other locales
    return const UnitPreferences(
      volume: VolumeUnit.ml,
      weight: WeightUnit.kg,
      length: LengthUnit.cm,
      temp: TempUnit.celsius,
      timeFormat: TimeFormat.h24,
      weekStart: WeekStart.sunday,
    );
  }

  UnitPreferences copyWith({
    VolumeUnit? volume,
    WeightUnit? weight,
    LengthUnit? length,
    TempUnit? temp,
    TimeFormat? timeFormat,
    WeekStart? weekStart,
  }) {
    return UnitPreferences(
      volume: volume ?? this.volume,
      weight: weight ?? this.weight,
      length: length ?? this.length,
      temp: temp ?? this.temp,
      timeFormat: timeFormat ?? this.timeFormat,
      weekStart: weekStart ?? this.weekStart,
    );
  }
}

/// Conversion helpers. Canonical input is always SI/metric.
class UnitConverter {
  UnitConverter._();

  // ml → oz: divide by 29.5735, round to 1 dp
  static const double _mlPerOz = 29.5735;

  // g → lb: divide by 453.592; remainder g → oz via divide by 28.3495
  static const double _gPerLb = 453.592;
  static const double _gPerOz = 28.3495;

  // g → kg: divide by 1000, round to 2 dp
  static const double _gPerKg = 1000.0;

  // cm → in: divide by 2.54, round to 1 dp
  static const double _cmPerIn = 2.54;

  /// Returns `(value, label)` e.g. `(2.1, 'oz')` or `(62.0, 'ml')`.
  /// [ml] is the canonical input in millilitres.
  static (double, String) displayVolume(double ml, VolumeUnit unit) {
    if (unit == VolumeUnit.oz) {
      final oz = _round1(ml / _mlPerOz);
      return (oz, 'oz');
    }
    return (_round1(ml), 'ml');
  }

  /// Returns `(formatted, label)` where formatted is e.g. `'7 lb 4 oz'` (lbOz)
  /// or `'3.3'` (kg) and label is `''` (lbOz, unit embedded) or `'kg'`.
  /// [grams] is the canonical input in grams.
  static (String, String) displayWeight(double grams, WeightUnit unit) {
    if (unit == WeightUnit.lbOz) {
      final lb = (grams / _gPerLb).floor();
      final remainingG = grams - lb * _gPerLb;
      final oz = (remainingG / _gPerOz).round();
      return ('$lb lb $oz oz', '');
    }
    // kg
    final kg = _round2(grams / _gPerKg);
    return (kg.toStringAsFixed(2 - (kg == kg.roundToDouble() ? 0 : 0)), 'kg');
  }

  /// Returns `(value, label)` e.g. `(20.1, 'in')` or `(51.0, 'cm')`.
  /// [cm] is the canonical input in centimetres.
  static (double, String) displayLength(double cm, LengthUnit unit) {
    if (unit == LengthUnit.inches) {
      return (_round1(cm / _cmPerIn), 'in');
    }
    return (_round1(cm), 'cm');
  }

  /// Returns `(value, label)` e.g. `(98.6, '°F')` or `(37.0, '°C')`.
  /// [celsius] is the canonical input in degrees Celsius.
  static (double, String) displayTemp(double celsius, TempUnit unit) {
    if (unit == TempUnit.fahrenheit) {
      return (_round1(celsius * 9 / 5 + 32), '°F');
    }
    return (_round1(celsius), '°C');
  }

  static double _round1(double v) => (v * 10).roundToDouble() / 10;
  static double _round2(double v) => (v * 100).roundToDouble() / 100;
}
