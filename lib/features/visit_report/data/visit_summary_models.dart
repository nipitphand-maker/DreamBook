import 'package:dreambook/core/models/temp_reading.dart';
import 'package:dreambook/core/models/vaccination.dart';
import 'package:flutter/foundation.dart';

@immutable
class DaySummary {
  const DaySummary({
    required this.date,
    required this.totalFeedOz,
    required this.wetDiapers,
    required this.soiledDiapers,
    required this.totalSleepMin,
    required this.longestSleepStretchMin,
    this.temperatures = const [],
  });

  /// Midnight UTC of this calendar day.
  final DateTime date;
  final double totalFeedOz;

  /// Diapers typed pee or mixed.
  final int wetDiapers;

  /// Diapers typed poop or mixed.
  final int soiledDiapers;
  final int totalSleepMin;
  final int longestSleepStretchMin;
  final List<TempReading> temperatures;
}

@immutable
class VisitSummaryData {
  const VisitSummaryData({
    required this.babyName,
    this.babyDob,
    required this.rangeStart,
    required this.rangeEnd,
    required this.days,
    required this.vaccinations,
  });

  final String babyName;
  final DateTime? babyDob;

  /// Inclusive start of the reporting window (midnight UTC).
  final DateTime rangeStart;

  /// Inclusive end of the reporting window (end-of-day UTC).
  final DateTime rangeEnd;

  final List<DaySummary> days;
  final List<VaccinationRecord> vaccinations;
}
