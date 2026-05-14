import 'dart:async';
import 'dart:typed_data';

import 'package:dreambook/core/sync/sync_error.dart';
import 'package:dreambook/core/sync/sync_server.dart';

/// Represents an encrypted_rows row as the fake server stores it.
class FakeEncryptedRow {
  FakeEncryptedRow({
    required this.id,
    required this.familyId,
    required this.tableName,
    required this.recordId,
    required this.version,
    required this.keyVersion,
    required this.ciphertext,
    required this.aadHash,
    required this.writtenByDevice,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String familyId;
  final String tableName;
  final String recordId;
  final int version;
  final int keyVersion;
  final Uint8List ciphertext;
  final Uint8List aadHash;
  final String writtenByDevice;
  DateTime updatedAt;
  DateTime? deletedAt;
}

class FakeDevice {
  FakeDevice({
    required this.deviceFp,
    required this.familyId,
    required this.devicePubKey,
    required this.role,
    required this.keyVersionAtJoin,
    this.revokedAt,
    this.wipeRequestedAt,
  });

  final String deviceFp;
  final String familyId;
  final Uint8List devicePubKey;
  String role;
  int keyVersionAtJoin;
  DateTime? revokedAt;
  DateTime? wipeRequestedAt;
}

class FakeFamily {
  FakeFamily({required this.id, this.currentKeyVersion = 1});
  final String id;
  int currentKeyVersion;
}

class FakeInvite {
  FakeInvite({
    required this.codeHash,
    required this.familyId,
    required this.salt,
    required this.wrappedKey,
    required this.expiresAt,
    this.consumedAt,
    this.claimDeviceFp,
    this.failedAttempts = 0,
  });

  final String codeHash;
  final String familyId;
  final Uint8List salt;
  final Uint8List wrappedKey;
  DateTime expiresAt;
  DateTime? consumedAt;
  String? claimDeviceFp;
  int failedAttempts;
}

class FakeKeyDistributionRow {
  FakeKeyDistributionRow({
    required this.familyId,
    required this.recipientDeviceFp,
    required this.keyVersion,
    required this.wrappedKey,
  });
  final String familyId;
  final String recipientDeviceFp;
  final int keyVersion;
  final Uint8List wrappedKey;
}

/// Behaves like the subset of Supabase REST + Realtime we depend on. The
/// implementation is deliberately strict: every check that production RLS or
/// an Edge Function performs is also performed here, so tests catch the same
/// mistakes locally as they would against the real server.
class FakeSupabaseServer implements SyncServer {
  final Map<String, FakeFamily> families = {};
  final Map<String, FakeDevice> devices = {}; // keyed by deviceFp
  final List<FakeEncryptedRow> encryptedRows = [];
  final Map<String, FakeInvite> invites = {}; // keyed by codeHash
  final List<FakeKeyDistributionRow> keyDistribution = [];

  /// Realtime stream: tests `listen()` on this for inserts/updates.
  final StreamController<FakeEncryptedRow> realtime = StreamController.broadcast();

  /// Used to simulate failures (network error, 403 RLS, etc.).
  bool simulateNetworkError = false;
  int? forcedStatusCode;

  /// Insert an encrypted row. Performs RLS-equivalent checks.
  ///
  /// Returns the inserted row on success. Throws [FakeHttpException] with a
  /// status code if the operation is rejected.
  Future<FakeEncryptedRow> insertEncryptedRowInternal({
    required FakeEncryptedRow row,
    required String authDeviceFp,
  }) async {
    _maybeFail();
    final device = devices[authDeviceFp];
    if (device == null || device.revokedAt != null) {
      throw const FakeHttpException(403, 'device revoked or unknown');
    }
    if (device.role != 'editor' && device.role != 'admin') {
      throw const FakeHttpException(403, 'role lacks write permission');
    }
    if (device.familyId != row.familyId) {
      throw const FakeHttpException(403, 'family mismatch');
    }
    final family = families[row.familyId];
    if (family == null || row.keyVersion != family.currentKeyVersion) {
      throw const FakeHttpException(403, 'key_version stale');
    }
    if (row.writtenByDevice != authDeviceFp) {
      throw const FakeHttpException(403, 'written_by_device must match auth.uid()');
    }
    encryptedRows.add(row);
    realtime.add(row);
    return row;
  }

  // ── SyncServer interface ────────────────────────────────────────────────

  @override
  Future<void> insertEncryptedRow({
    required String id,
    required String familyId,
    required String tableName,
    required String recordId,
    required int version,
    required int keyVersion,
    required Uint8List ciphertext,
    required Uint8List aadHash,
    required String writtenByDevice,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) async {
    // Delegate to the existing internal-helper insert; we'll find auth from
    // writtenByDevice (production has auth.uid()::bytea, here we trust the
    // value passed because tests construct it explicitly).
    final row = FakeEncryptedRow(
      id: id,
      familyId: familyId,
      tableName: tableName,
      recordId: recordId,
      version: version,
      keyVersion: keyVersion,
      ciphertext: ciphertext,
      aadHash: aadHash,
      writtenByDevice: writtenByDevice,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
    // Use writtenByDevice as the auth identity for the RLS-equivalent check.
    // Translate FakeHttpException / FakeNetworkException into SyncServer
    // interface error types so SyncWorker never needs to import test fakes.
    try {
      await insertEncryptedRowInternal(row: row, authDeviceFp: writtenByDevice);
    } on FakeNetworkException catch (e) {
      throw SyncNetworkError(e);
    } on FakeHttpException catch (e) {
      if (e.statusCode == 403) {
        throw SyncRlsReject(e.message);
      }
      throw SyncNetworkError(e);
    }
  }

  @override
  Future<List<RemoteEncryptedRow>> pullRows({
    required String familyId,
    DateTime? since,
  }) async {
    // For test convenience, allow any caller to pull (no auth gate here).
    // The push path's RLS check is what tests exercise; pull-side RLS is
    // covered separately in integration tests that set up devices.
    final filtered = encryptedRows.where((r) =>
        r.familyId == familyId &&
        (since == null || r.updatedAt.isAfter(since)));
    return filtered
        .map((r) => RemoteEncryptedRow(
              tableName: r.tableName,
              recordId: r.recordId,
              version: r.version,
              keyVersion: r.keyVersion,
              familyId: r.familyId,
              ciphertext: r.ciphertext,
              aadHash: r.aadHash,
              writtenByDevice: r.writtenByDevice,
              updatedAt: r.updatedAt,
              deletedAt: r.deletedAt,
            ))
        .toList();
  }

  @override
  Stream<RemoteEncryptedRow> realtimeStream({required String familyId}) {
    return realtime.stream
        .where((row) => row.familyId == familyId)
        .map((row) => RemoteEncryptedRow(
              tableName: row.tableName,
              recordId: row.recordId,
              version: row.version,
              keyVersion: row.keyVersion,
              familyId: row.familyId,
              ciphertext: row.ciphertext,
              aadHash: row.aadHash,
              writtenByDevice: row.writtenByDevice,
              updatedAt: row.updatedAt,
              deletedAt: row.deletedAt,
            ));
  }

  // ── Legacy pull (kept for backwards compat in existing tests) ───────────

  /// Pull encrypted rows updated after [sinceUtc] for [familyId].
  List<FakeEncryptedRow> pullRowsInternal({
    required String familyId,
    required String authDeviceFp,
    DateTime? sinceUtc,
  }) {
    final device = devices[authDeviceFp];
    if (device == null || device.revokedAt != null || device.familyId != familyId) {
      throw const FakeHttpException(403, 'device cannot read this family');
    }
    return encryptedRows
        .where((r) =>
            r.familyId == familyId &&
            (sinceUtc == null || r.updatedAt.isAfter(sinceUtc)))
        .toList();
  }

  /// Pull wrapped-key rows for one device.
  List<FakeKeyDistributionRow> pullKeyDistribution({
    required String recipientDeviceFp,
  }) {
    final device = devices[recipientDeviceFp];
    if (device == null || device.revokedAt != null) {
      throw const FakeHttpException(403, 'device cannot read key_distribution');
    }
    return keyDistribution
        .where((r) => r.recipientDeviceFp == recipientDeviceFp)
        .toList();
  }

  /// Edge Function: claim_invite — modeled here.
  Future<Map<String, dynamic>> claimInvite({
    required String codeHash,
    required String deviceFp,
    required Uint8List devicePubKey,
  }) async {
    final invite = invites[codeHash];
    if (invite == null) throw const FakeHttpException(404, 'invite not found');
    if (invite.failedAttempts >= 5) {
      throw const FakeHttpException(410, 'invite dead (too many failed attempts)');
    }
    if (invite.expiresAt.isBefore(DateTime.now().toUtc())) {
      throw const FakeHttpException(410, 'invite expired');
    }
    if (invite.consumedAt != null) {
      throw const FakeHttpException(410, 'invite already consumed');
    }
    invite.consumedAt = DateTime.now().toUtc();
    invite.claimDeviceFp = deviceFp;
    final family = families[invite.familyId]!;
    devices[deviceFp] = FakeDevice(
      deviceFp: deviceFp,
      familyId: invite.familyId,
      devicePubKey: devicePubKey,
      role: 'editor',
      keyVersionAtJoin: family.currentKeyVersion,
    );
    keyDistribution.add(
      FakeKeyDistributionRow(
        familyId: invite.familyId,
        recipientDeviceFp: deviceFp,
        keyVersion: family.currentKeyVersion,
        wrappedKey: invite.wrappedKey,
      ),
    );
    return {
      'salt': invite.salt,
      'wrapped_key': invite.wrappedKey,
      'family_id': invite.familyId,
      'key_version': family.currentKeyVersion,
    };
  }

  /// Edge Function: revoke_caregiver.
  Future<List<Map<String, dynamic>>> revokeCaregiver({
    required String callerDeviceFp,
    required String targetDeviceFp,
  }) async {
    final caller = devices[callerDeviceFp];
    if (caller == null || caller.role != 'admin' || caller.revokedAt != null) {
      throw const FakeHttpException(403, 'caller not admin');
    }
    final target = devices[targetDeviceFp];
    if (target == null || target.familyId != caller.familyId) {
      throw const FakeHttpException(404, 'target not in family');
    }
    target.revokedAt = DateTime.now().toUtc();
    target.wipeRequestedAt = DateTime.now().toUtc();
    final family = families[target.familyId]!;
    family.currentKeyVersion += 1;
    return devices.values
        .where((d) =>
            d.familyId == family.id &&
            d.revokedAt == null &&
            d.deviceFp != targetDeviceFp)
        .map((d) => {
              'device_fp': d.deviceFp,
              'device_pub_key': d.devicePubKey,
            })
        .toList();
  }

  void _maybeFail() {
    if (simulateNetworkError) {
      throw const FakeNetworkException();
    }
    final code = forcedStatusCode;
    if (code != null) {
      throw FakeHttpException(code, 'forced failure');
    }
  }

  void dispose() {
    realtime.close();
  }
}

class FakeHttpException implements Exception {
  const FakeHttpException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => 'FakeHttpException($statusCode): $message';
}

class FakeNetworkException implements Exception {
  const FakeNetworkException();
  @override
  String toString() => 'FakeNetworkException';
}
