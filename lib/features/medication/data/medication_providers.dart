import 'package:dreambook/core/models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'medication_repository.dart';

export 'medication_repository.dart' show medicationRepositoryProvider;

final medicationTodayProvider =
    FutureProvider.family<List<MedicationDose>, String>((ref, babyId) async {
  final now = DateTime.now();
  final dayStart = DateTime(now.year, now.month, now.day);
  return ref.read(medicationRepositoryProvider).forBabyToday(babyId, dayStart);
});
