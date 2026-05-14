/// Canonical AAD format per spec §5.1. Used on both seal (push) and
/// open (pull) so the binding is symmetric.
class EncryptedRow {
  EncryptedRow._();

  static String aadFor({
    required String tableName,
    required String recordId,
    required int version,
    required String familyId,
    required int keyVersion,
  }) =>
      '$tableName|$recordId|$version|$familyId|$keyVersion';
}
