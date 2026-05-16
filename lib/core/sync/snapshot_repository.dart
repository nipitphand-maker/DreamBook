import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../crypto/family_key_service.dart';
import '../crypto/snapshot_service.dart';
import '../providers/shared_preferences_provider.dart';
import '../router/app_router.dart' show kOnboardingDoneKey;
import 'supabase_sync_server.dart';
import 'sync_constants.dart';

class SnapshotPassphraseError implements Exception {
  const SnapshotPassphraseError();
}

class SnapshotNotFoundError implements Exception {
  const SnapshotNotFoundError();
}

class SnapshotRateLimitError implements Exception {
  const SnapshotRateLimitError();
}

class SnapshotRepository {
  SnapshotRepository({
    required SupabaseClient supabase,
    required FamilyKeyService keyService,
    required SharedPreferences prefs,
    SnapshotService? snapshotService,
  })  : _supabase = supabase,
        _keyService = keyService,
        _prefs = prefs,
        _snapshotService = snapshotService ?? SnapshotService();

  final SupabaseClient _supabase;
  final FamilyKeyService _keyService;
  final SharedPreferences _prefs;
  final SnapshotService _snapshotService;

  // _kSnapshotVersion = 0 is the canonical AAD placeholder used on both
  // upload and restore so the payload AAD is consistent regardless of the
  // server-assigned snapshot version number.
  static const _kSnapshotVersion = 0;

  /// Pulls all encrypted rows for [familyId], encrypts them, and uploads to
  /// the upload_snapshot Edge Function. Returns the EF-assigned version number.
  Future<int> upload({
    required String familyId,
    required String passphrase,
  }) async {
    final familyKey = await _keyService.read(familyId: familyId);
    if (familyKey == null) throw StateError('K_family not found for $familyId');

    final syncServer = SupabaseSyncServer(_supabase);
    final remoteRows = await syncServer.pullRows(familyId: familyId);

    final serializedRows = remoteRows.map((r) => {
      'table_name': r.tableName,
      'record_id': r.recordId,
      'version': r.version,
      'key_version': r.keyVersion,
      'family_id': r.familyId,
      'ciphertext': base64.encode(r.ciphertext),
      'aad_hash': base64.encode(r.aadHash),
      'written_by_device': r.writtenByDevice,
      'updated_at': r.updatedAt.toIso8601String(),
      'deleted_at': r.deletedAt?.toIso8601String(),
    }).toList();

    final prepared = await _snapshotService.prepare(
      passphrase: passphrase,
      familyKey: familyKey.bytes,
      familyId: familyId,
      keyVersion: familyKey.keyVersion,
      snapshotVersion: _kSnapshotVersion,
      rows: serializedRows,
    );

    final FunctionResponse response;
    try {
      response = await _supabase.functions.invoke(
        'upload_snapshot',
        body: {
          'wrapped_key_b64': base64.encode(prepared.wrappedKey),
          'salt_b64': base64.encode(prepared.salt),
          'key_version': familyKey.keyVersion,
          'payload_b64': base64.encode(prepared.encryptedPayload),
          'payload_hash_b64': base64.encode(prepared.payloadHash),
        },
      );
    } on FunctionException catch (e) {
      if (e.status == 429) throw const SnapshotRateLimitError();
      rethrow;
    }

    final data = response.data as Map<String, dynamic>;
    return data['version'] as int;
  }

  /// Downloads and decrypts a snapshot from the restore_snapshot EF,
  /// installs K_family, marks onboarding done, and re-pushes all rows to
  /// Supabase (idempotent — covers server-data-loss recovery).
  ///
  /// Does NOT trigger syncNow() — caller is responsible for invalidating
  /// [syncLifecycleControllerProvider] and calling syncNow().
  ///
  /// Returns the family_id returned by the EF.
  Future<String> restore({
    required String lookupHashB64,
    required String normalizedCode,
    required Uint8List devicePubKey,
    int? version,
  }) async {
    final body = <String, dynamic>{
      'lookup_hash_b64': lookupHashB64,
      'device_pub_key_b64': base64.encode(devicePubKey),
    };
    if (version != null) body['version'] = version;

    final FunctionResponse response;
    try {
      response = await _supabase.functions.invoke('restore_snapshot', body: body);
    } on FunctionException catch (e) {
      if (e.status == 404) throw const SnapshotNotFoundError();
      if (e.status == 429) throw const SnapshotRateLimitError();
      rethrow;
    }

    final data = response.data as Map<String, dynamic>;
    final familyId = data['family_id'] as String;
    final wrappedKey = base64.decode(data['wrapped_key_b64'] as String);
    final salt = base64.decode(data['salt_b64'] as String);
    final keyVersion = data['key_version'] as int;
    final encryptedPayload = base64.decode(data['payload_b64'] as String);
    final payloadHash = base64.decode(data['payload_hash_b64'] as String);

    // Verify integrity before attempting decryption.
    final recomputed = await Sha256().hash(encryptedPayload);
    if (!_bytesEqual(payloadHash, Uint8List.fromList(recomputed.bytes))) {
      throw const FormatException('Snapshot payload hash mismatch');
    }

    RestoredSnapshot restored;
    try {
      restored = await _snapshotService.restore(
        passphrase: normalizedCode,
        encryptedPayload: encryptedPayload,
        wrappedKey: Uint8List.fromList(wrappedKey),
        salt: Uint8List.fromList(salt),
        familyId: familyId,
        keyVersion: keyVersion,
        snapshotVersion: _kSnapshotVersion, // must match upload-time AAD
      );
    } on SecretBoxAuthenticationError {
      throw const SnapshotPassphraseError();
    }

    await _keyService.install(
      familyId: familyId,
      bytes: restored.familyKey,
      keyVersion: keyVersion,
    );

    await _prefs.setString(kFamilyIdPrefsKey, familyId);
    await _prefs.setBool(kOnboardingDoneKey, true);

    // Re-push rows to Supabase (idempotent upsert — covers server-data-loss).
    final syncServer = SupabaseSyncServer(_supabase);
    for (final row in restored.rows) {
      await syncServer.insertEncryptedRow(
        id: row['record_id'] as String,
        familyId: row['family_id'] as String,
        tableName: row['table_name'] as String,
        recordId: row['record_id'] as String,
        version: row['version'] as int,
        keyVersion: row['key_version'] as int,
        ciphertext: base64.decode(row['ciphertext'] as String),
        aadHash: base64.decode(row['aad_hash'] as String),
        writtenByDevice: row['written_by_device'] as String,
        updatedAt: DateTime.parse(row['updated_at'] as String),
        deletedAt: row['deleted_at'] == null
            ? null
            : DateTime.parse(row['deleted_at'] as String),
      );
    }

    return familyId;
  }


  bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}

final snapshotRepositoryProvider = Provider<SnapshotRepository>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SnapshotRepository(
    supabase: Supabase.instance.client,
    keyService: FamilyKeyService(const FlutterSecureStorage()),
    prefs: prefs,
  );
});
