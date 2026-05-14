import 'dart:typed_data';

import 'package:dreambook/core/sync/realtime_subscriber.dart';
import 'package:dreambook/core/sync/sync_server.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_fakes/fake_supabase_server.dart';

void main() {
  late FakeSupabaseServer server;
  late RealtimeSubscriber subscriber;
  late List<RemoteEncryptedRow> received;

  setUp(() {
    server = FakeSupabaseServer();
    received = <RemoteEncryptedRow>[];
    subscriber = RealtimeSubscriber(
      server: server,
      onIncomingRow: (row) async {
        received.add(row);
      },
    );
  });

  tearDown(() async {
    await subscriber.disconnect();
    server.dispose();
  });

  group('RealtimeSubscriber', () {
    test('connect() forwards incoming rows to callback', () async {
      await subscriber.connect(familyId: 'fam-1');
      final row = FakeEncryptedRow(
        id: 'r1',
        familyId: 'fam-1',
        tableName: 'feed',
        recordId: 'feed-1',
        version: 1,
        keyVersion: 1,
        ciphertext: Uint8List(50),
        aadHash: Uint8List(64),
        writtenByDevice: 'device-X',
        updatedAt: DateTime.now().toUtc(),
      );
      server.realtime.add(row);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(received.length, 1);
      expect(received.first.recordId, 'feed-1');
    });

    test('only forwards rows matching subscribed family_id', () async {
      await subscriber.connect(familyId: 'fam-A');
      final otherFamily = FakeEncryptedRow(
        id: 'r2',
        familyId: 'fam-B',
        tableName: 'feed',
        recordId: 'feed-2',
        version: 1,
        keyVersion: 1,
        ciphertext: Uint8List(50),
        aadHash: Uint8List(64),
        writtenByDevice: 'device-Y',
        updatedAt: DateTime.now().toUtc(),
      );
      server.realtime.add(otherFamily);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(received, isEmpty);
    });

    test('disconnect() stops forwarding', () async {
      await subscriber.connect(familyId: 'fam-1');
      await subscriber.disconnect();
      server.realtime.add(FakeEncryptedRow(
        id: 'r3',
        familyId: 'fam-1',
        tableName: 'feed',
        recordId: 'feed-3',
        version: 1,
        keyVersion: 1,
        ciphertext: Uint8List(50),
        aadHash: Uint8List(64),
        writtenByDevice: 'device-X',
        updatedAt: DateTime.now().toUtc(),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(received, isEmpty);
    });
  });
}
