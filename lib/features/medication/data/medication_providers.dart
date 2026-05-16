import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/core/providers/day_start_hour_provider.dart';
import 'package:dreambook/core/utils/day_boundary.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'medication_repository.dart';

export 'medication_repository.dart' show medicationRepositoryProvider;

/// "Today" doses for [babyId], aligned to the user's [dayStartHourProvider]
/// preference so that overnight doses bucket with the feed/diaper/sleep
/// "today" view (a 2 AM dose with dayStartHour=6 belongs to the prior
/// logical day, matching how feeds and diapers handle the same time).
final medicationTodayProvider =
    FutureProvider.family<List<MedicationDose>, String>((ref, babyId) async {
  final dayStartHour = ref.watch(dayStartHourProvider);
  final dayStart = currentLogicalDayStart(DateTime.now(), dayStartHour);
  return ref.read(medicationRepositoryProvider).forBabyToday(babyId, dayStart);
});
