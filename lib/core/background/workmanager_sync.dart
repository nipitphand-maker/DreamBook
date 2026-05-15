import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

const _taskNamePeriodic = 'dev.niyoko.dreambook.sync.periodic';

/// Top-level callback required by WorkManager — must be a top-level function.
/// WorkManager spawns a fresh Dart isolate; this function initialises the
/// minimal context needed to trigger a sync cycle.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    // NOTE: A full Riverpod/SQLCipher stack cannot be initialised here safely
    // without the full app boot sequence. Phase 3 will wire a lightweight sync
    // bootstrap. For now we record the background wake-up and return success
    // so WorkManager keeps scheduling us.
    debugPrint('[DreamBook] WorkManager task fired: $taskName');
    return Future.value(true);
  });
}

/// Registers the inexact periodic WorkManager task. Safe to call on every
/// app launch — WorkManager deduplicates by unique name.
Future<void> registerBackgroundSync() async {
  await Workmanager().registerPeriodicTask(
    _taskNamePeriodic,
    _taskNamePeriodic,
    // 15 minutes is the WorkManager minimum periodic interval.
    frequency: const Duration(minutes: 15),
    constraints: Constraints(
      networkType: NetworkType.connected,
      requiresBatteryNotLow: true,
      requiresCharging: true,
    ),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    // IMPORTANT: No setExact, no exactAllowWhileIdle — inexact only.
    // See tool/check_no_exact_alarms.sh
  );
}
