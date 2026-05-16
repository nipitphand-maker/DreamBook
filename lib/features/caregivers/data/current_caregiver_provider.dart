import 'package:dreambook/core/db/database_provider.dart';
import 'package:dreambook/core/models/caregiver.dart';
import 'package:dreambook/core/providers/device_id_provider.dart';
import 'package:dreambook/features/caregivers/data/caregiver_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The "self" caregiver row for the current device, if one exists. Returns
/// null when no caregiver row has been seeded yet (e.g. tests, fresh install
/// before [CaregiverRepository.getOrCreateSelf] runs).
///
/// Looks up by `device_id = deviceIdProvider`. Watches [appDatabaseProvider]
/// so role/displayName changes propagate to the UI without manual invalidate.
final currentCaregiverProvider = FutureProvider<Caregiver?>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final deviceId = ref.watch(deviceIdProvider);
  final rows = await db.query(
    'caregiver',
    where: 'device_id = ? AND revoked_at IS NULL AND deleted_at IS NULL',
    whereArgs: [deviceId],
    orderBy: 'joined_at ASC',
    limit: 1,
  );
  if (rows.isEmpty) return null;
  return Caregiver.fromRow(rows.first);
});

/// The current device's caregiver id (the value stored in `*.logged_by` on
/// rows authored from this device). Null until the self-caregiver is seeded.
final currentCaregiverIdProvider = Provider<String?>(
  (ref) => ref.watch(currentCaregiverProvider).value?.id,
);

/// Effective role for the current device. Defaults to [CaregiverRole.editor]
/// while the self-caregiver is loading or absent — keeps the device usable
/// on first launch (pre-getOrCreateSelf) rather than locking it to read-only.
final currentCaregiverRoleProvider = Provider<CaregiverRole>(
  (ref) =>
      ref.watch(currentCaregiverProvider).value?.role ?? CaregiverRole.editor,
);

/// Whether the current device can edit/delete a row authored by [rowLoggedBy].
///
/// Rules (matches the spec for the history list role-gating):
/// - [CaregiverRole.readOnly] → never.
/// - [CaregiverRole.editor] → only when [rowLoggedBy] equals the device's
///   own caregiver id. A null [rowLoggedBy] is treated as "own" for editors
///   because legacy rows (logged before caregiver attribution shipped) have
///   no author and would otherwise be permanently locked.
/// - [CaregiverRole.admin] → always.
bool canEditRow({
  required CaregiverRole role,
  required String? rowLoggedBy,
  required String? selfCaregiverId,
}) {
  switch (role) {
    case CaregiverRole.readOnly:
      return false;
    case CaregiverRole.admin:
      return true;
    case CaregiverRole.editor:
      if (rowLoggedBy == null) return true;
      if (selfCaregiverId == null) return false;
      return rowLoggedBy == selfCaregiverId;
  }
}
