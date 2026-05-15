// test/integration/_helpers/real_supabase_harness.dart
//
// Ring 2 integration tests use this harness to provision an isolated
// family + 2 devices against a local supabase started by
// tool/test_supabase_start.sh. Each call to freshFamily() mints a unique
// family_id; dispose() wipes only that family_id's rows.

import 'dart:io';
import 'dart:typed_data';

import 'package:dreambook/core/sync/supabase_sync_server.dart';
import 'package:dreambook/core/sync/sync_server.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

class RealSupabaseEnv {
  RealSupabaseEnv({
    required this.apiUrl,
    required this.anonKey,
    required this.serviceRoleKey,
  });
  final String apiUrl;
  final String anonKey;
  final String serviceRoleKey;

  static RealSupabaseEnv load() {
    final file = File('.env.test.supabase');
    if (!file.existsSync()) {
      throw StateError(
        'Missing .env.test.supabase — run ./tool/test_supabase_start.sh first',
      );
    }
    final map = <String, String>{};
    for (final line in file.readAsLinesSync()) {
      if (line.isEmpty || line.startsWith('#')) continue;
      final i = line.indexOf('=');
      if (i <= 0) continue;
      map[line.substring(0, i)] = line.substring(i + 1);
    }
    return RealSupabaseEnv(
      apiUrl: map['SUPABASE_TEST_API_URL']!,
      anonKey: map['SUPABASE_TEST_ANON_KEY']!,
      serviceRoleKey: map['SUPABASE_TEST_SERVICE_ROLE_KEY']!,
    );
  }
}

class FreshFamilyFixture {
  FreshFamilyFixture({
    required this.familyId,
    required this.deviceA,
    required this.deviceB,
    required this.clientA,
    required this.clientB,
    required this.serverA,
    required this.serverB,
    required this.serviceClient,
    required Future<void> Function() cleanup,
  }) : _cleanup = cleanup;

  final String familyId;
  final String deviceA;
  final String deviceB;
  final SupabaseClient clientA;
  final SupabaseClient clientB;
  final SyncServer serverA;
  final SyncServer serverB;
  final SupabaseClient serviceClient;
  final Future<void> Function() _cleanup;

  Future<void> dispose() => _cleanup();
}

class RealSupabaseHarness {
  RealSupabaseHarness._(this.env);
  final RealSupabaseEnv env;

  static RealSupabaseHarness? _instance;

  static Future<RealSupabaseHarness> boot() async {
    if (_instance != null) return _instance!;
    final env = RealSupabaseEnv.load();
    final probe = await Process.run('curl', [
      '-fsS',
      '${env.apiUrl}/rest/v1/',
      '-H',
      'apikey: ${env.anonKey}',
    ]);
    if (probe.exitCode != 0) {
      throw StateError('Supabase API not reachable at ${env.apiUrl}');
    }
    _instance = RealSupabaseHarness._(env);
    return _instance!;
  }

  final _uuid = const Uuid();

  Future<FreshFamilyFixture> freshFamily() async {
    final familyId = _uuid.v4();
    final deviceA = _randomHex(16);
    final deviceB = _randomHex(16);

    final service = SupabaseClient(env.apiUrl, env.serviceRoleKey);

    await service.from('families').insert({
      'id': familyId,
      'current_key_version': 1,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });

    final clientA = SupabaseClient(env.apiUrl, env.anonKey);
    final authA = await clientA.auth.signInAnonymously();
    final clientB = SupabaseClient(env.apiUrl, env.anonKey);
    final authB = await clientB.auth.signInAnonymously();

    await service.from('family_devices').insert([
      {
        'family_id': familyId,
        'device_fp': r'\x' + deviceA,
        'device_pub_key': r'\x' + _randomHex(32),
        'role': 'admin',
        'key_version_at_join': 1,
        'auth_user_id': authA.user!.id,
      },
      {
        'family_id': familyId,
        'device_fp': r'\x' + deviceB,
        'device_pub_key': r'\x' + _randomHex(32),
        'role': 'editor',
        'key_version_at_join': 1,
        'auth_user_id': authB.user!.id,
      },
    ]);

    final serverA = SupabaseSyncServer(clientA);
    final serverB = SupabaseSyncServer(clientB);

    Future<void> cleanup() async {
      try {
        await service.from('encrypted_rows').delete().eq('family_id', familyId);
        await service.from('key_distribution').delete().eq('family_id', familyId);
        await service.from('family_devices').delete().eq('family_id', familyId);
        await service.from('families').delete().eq('id', familyId);
        try { await service.auth.admin.deleteUser(authA.user!.id); } catch (_) {}
        try { await service.auth.admin.deleteUser(authB.user!.id); } catch (_) {}
      } finally {
        await clientA.dispose();
        await clientB.dispose();
        await service.dispose();
      }
    }

    return FreshFamilyFixture(
      familyId: familyId,
      deviceA: deviceA,
      deviceB: deviceB,
      clientA: clientA,
      clientB: clientB,
      serverA: serverA,
      serverB: serverB,
      serviceClient: service,
      cleanup: cleanup,
    );
  }

  String _randomHex(int bytes) {
    final u = _uuid.v4().replaceAll('-', '');
    final padded = (u + u + u + u).substring(0, bytes * 2);
    return padded;
  }
}

class TestRowBytes {
  TestRowBytes(this.ciphertext, this.aadHash);
  final Uint8List ciphertext;
  final Uint8List aadHash;

  static TestRowBytes deterministic(String marker) {
    final ct = Uint8List.fromList(
      List<int>.generate(64, (i) => marker.codeUnitAt(i % marker.length) ^ i),
    );
    final hash = Uint8List.fromList(
      List<int>.generate(32, (i) => i ^ marker.length),
    );
    return TestRowBytes(ct, hash);
  }
}

void skipIfNoSupabase() {
  if (!File('.env.test.supabase').existsSync()) {
    markTestSkipped(
      'Skipping Ring 2 — run ./tool/test_supabase_start.sh first',
    );
  }
}
