import 'package:dreambook/core/models/models.dart';
import 'package:dreambook/features/pump/data/pump_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Number of pump sessions recorded today for [babyId].
///
/// Derived from [pumpTodayProvider] — one read path, free consistency
/// with the list. Rebuilds whenever the underlying list changes.
final pumpCountTodayProvider = Provider.family<AsyncValue<int>, String>(
  (ref, babyId) => ref.watch(pumpTodayProvider(babyId)).whenData(
        (s) => s.length,
      ),
);

/// Total pumped volume (leftOz + rightOz) across all sessions today for [babyId].
final pumpOzTodayProvider = Provider.family<AsyncValue<double>, String>(
  (ref, babyId) => ref.watch(pumpTodayProvider(babyId)).whenData(
        (sessions) => sessions.fold<double>(
          0.0,
          (sum, s) => sum + s.leftOz + s.rightOz,
        ),
      ),
);

/// The most recent pump session today for [babyId], or null if none.
///
/// `pumpTodayProvider` is already ordered `started_at DESC`, so `s.first`
/// yields the latest session.
final lastPumpTodayProvider =
    Provider.family<AsyncValue<PumpSession?>, String>(
  (ref, babyId) => ref.watch(pumpTodayProvider(babyId)).whenData(
        (s) => s.isEmpty ? null : s.first,
      ),
);
