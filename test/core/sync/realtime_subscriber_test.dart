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
    await subscriber.dispose();
    server.dispose();
  });

  // The fake stores FakeEncryptedRow on its realtime controller and
  // re-maps to RemoteEncryptedRow inside realtimeStream. Tests therefore
  // construct FakeEncryptedRow when pushing events.
  FakeEncryptedRow makeFakeRow(String familyId, String recordId) =>
      FakeEncryptedRow(
        id: 'r-$recordId',
        familyId: familyId,
        tableName: 'feed',
        recordId: recordId,
        version: 1,
        keyVersion: 1,
        ciphertext: Uint8List(50),
        aadHash: Uint8List(64),
        writtenByDevice: 'device-X',
        updatedAt: DateTime.now().toUtc(),
      );

  group('RealtimeSubscriber (legacy public API)', () {
    test('connect() forwards incoming rows to callback', () async {
      await subscriber.connect(familyId: 'fam-1');
      server.realtime.add(makeFakeRow('fam-1', 'feed-1'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(received.length, 1);
      expect(received.first.recordId, 'feed-1');
    });

    test('only forwards rows matching subscribed family_id', () async {
      await subscriber.connect(familyId: 'fam-A');
      server.realtime.add(makeFakeRow('fam-B', 'feed-2'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(received, isEmpty);
    });

    test('disconnect() stops forwarding', () async {
      await subscriber.connect(familyId: 'fam-1');
      await subscriber.disconnect();
      server.realtime.add(makeFakeRow('fam-1', 'feed-3'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(received, isEmpty);
    });
  });

  group('RealtimeSubscriber state machine', () {
    test('initial status is offline before connect()', () {
      expect(subscriber.status, RealtimeStatus.offline);
      expect(subscriber.isConnected, isFalse);
      expect(subscriber.reconnectAttempt, 0);
    });

    test('connect() transitions to connected', () async {
      final transitions = <RealtimeStatus>[];
      final statusSub = subscriber.statusStream.listen(transitions.add);
      await subscriber.connect(familyId: 'fam-1');
      // Allow the status broadcast to flush.
      await Future<void>.delayed(Duration.zero);
      expect(subscriber.status, RealtimeStatus.connected);
      expect(transitions, contains(RealtimeStatus.connected));
      await statusSub.cancel();
    });

    test('stream error transitions to degraded and schedules reconnect',
        () async {
      // Zero backoff so the reconnect fires on the next event loop tick.
      subscriber = RealtimeSubscriber(
        server: server,
        onIncomingRow: (row) async => received.add(row),
        backoffStrategy: (_) => Duration.zero,
      );
      final transitions = <RealtimeStatus>[];
      final statusSub = subscriber.statusStream.listen(transitions.add);
      await subscriber.connect(familyId: 'fam-1');
      await Future<void>.delayed(Duration.zero);

      // Inject a stream error — the .where/.map transformers propagate it
      // straight to the subscriber's onError handler.
      server.realtime.addError(StateError('socket dropped'));
      // Microtask flush + Timer(zero) drain.
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(transitions, containsAllInOrder(<RealtimeStatus>[
        RealtimeStatus.connected,
        RealtimeStatus.degraded,
        RealtimeStatus.connected, // immediate reconnect with zero backoff
      ]));
      expect(subscriber.status, RealtimeStatus.connected);
      await statusSub.cancel();
    });

    test('reconnect attempt counter advances on each failure', () async {
      subscriber = RealtimeSubscriber(
        server: server,
        onIncomingRow: (row) async => received.add(row),
        backoffStrategy: (_) => Duration.zero,
      );
      await subscriber.connect(familyId: 'fam-1');
      await Future<void>.delayed(Duration.zero);
      expect(subscriber.reconnectAttempt, 0);

      // Each error bumps the attempt counter to N, then the immediate
      // reconnect (zero backoff) succeeds and the counter holds until the
      // stable window resets it. Inject several errors without waiting for
      // the stable window so the counter accumulates.
      server.realtime.addError(StateError('drop 1'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(subscriber.reconnectAttempt, 1);

      // Once the reconnect succeeds the subscriber is back to connected,
      // but until the stable window elapses the counter remains. Force
      // another drop right away.
      server.realtime.addError(StateError('drop 2'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(subscriber.reconnectAttempt, 2);
    });

    test('10 consecutive failures exhaust budget and go offline', () async {
      subscriber = RealtimeSubscriber(
        server: server,
        onIncomingRow: (row) async => received.add(row),
        // The server-side stream is always available, so to simulate "10
        // failures in a row" we close the fake controller — every reconnect
        // immediately sees onDone, which routes through _handleError.
        backoffStrategy: (_) => Duration.zero,
      );
      await subscriber.connect(familyId: 'fam-1');
      await Future<void>.delayed(Duration.zero);

      // Closing the broadcast controller delivers onDone to the current
      // listener; the subscriber then opens a fresh subscription on the
      // (now-closed) controller, which immediately fires onDone again.
      // Each cycle increments _attempt until the budget is hit.
      await server.realtime.close();
      // Pump the event loop until the state machine settles.
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        if (subscriber.status == RealtimeStatus.offline) break;
      }
      expect(subscriber.status, RealtimeStatus.offline);
      expect(subscriber.reconnectAttempt, 10);
    });

    test('successful reconnect within stable window keeps attempt counter; '
        'staying connected past the stable window resets it', () async {
      subscriber = RealtimeSubscriber(
        server: server,
        onIncomingRow: (row) async => received.add(row),
        backoffStrategy: (_) => Duration.zero,
        stableConnectionWindow: const Duration(milliseconds: 50),
      );
      await subscriber.connect(familyId: 'fam-1');
      await Future<void>.delayed(Duration.zero);

      // First drop -> reconnect succeeds. _attempt is still 1 at this moment.
      server.realtime.addError(StateError('drop'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(subscriber.status, RealtimeStatus.connected);
      expect(subscriber.reconnectAttempt, 1);

      // Wait past the stable window — counter should clear back to 0.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(subscriber.reconnectAttempt, 0);
      expect(subscriber.status, RealtimeStatus.connected);
    });

    test('disconnect() cancels a pending reconnect and goes offline',
        () async {
      // Use a long backoff so the reconnect timer is still pending when
      // we call disconnect() — that's the window we're testing.
      subscriber = RealtimeSubscriber(
        server: server,
        onIncomingRow: (row) async => received.add(row),
        backoffStrategy: (_) => const Duration(seconds: 5),
      );
      await subscriber.connect(familyId: 'fam-1');
      await Future<void>.delayed(Duration.zero);

      server.realtime.addError(StateError('drop'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(subscriber.status, RealtimeStatus.degraded);
      expect(subscriber.reconnectAttempt, 1);

      await subscriber.disconnect();
      expect(subscriber.status, RealtimeStatus.offline);

      // Push a row after the long backoff would normally have elapsed.
      // Because disconnect() cancelled the pending timer, the subscriber
      // must NOT have re-opened the stream and must NOT forward the row.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      // We cannot easily fast-forward the 5s timer without a fake clock,
      // but we *can* verify the timer never re-arms a subscription: no
      // new rows are forwarded and status remains offline.
      received.clear();
      server.realtime.add(makeFakeRow('fam-1', 'late'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(received, isEmpty);
      expect(subscriber.status, RealtimeStatus.offline);
    });

    test('connect() while degraded resets the reconnect budget', () async {
      subscriber = RealtimeSubscriber(
        server: server,
        onIncomingRow: (row) async => received.add(row),
        // Long backoff so we can observe the degraded state before any
        // reconnect attempt completes.
        backoffStrategy: (_) => const Duration(seconds: 5),
      );
      await subscriber.connect(familyId: 'fam-1');
      await Future<void>.delayed(Duration.zero);

      server.realtime.addError(StateError('drop'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(subscriber.reconnectAttempt, 1);
      expect(subscriber.status, RealtimeStatus.degraded);

      // Caller invokes connect() to force an immediate reconnection
      // attempt; the state machine should drop back to attempt 0 and the
      // status should swing to connected.
      await subscriber.connect(familyId: 'fam-1');
      await Future<void>.delayed(Duration.zero);
      expect(subscriber.reconnectAttempt, 0);
      expect(subscriber.status, RealtimeStatus.connected);
    });

    test('reconnectDelay schedule: 1s, 2s, 4s, 8s, 16s, then capped at 30s',
        () {
      expect(RealtimeSubscriber.reconnectDelay(0), Duration.zero);
      expect(RealtimeSubscriber.reconnectDelay(1), const Duration(seconds: 1));
      expect(RealtimeSubscriber.reconnectDelay(2), const Duration(seconds: 2));
      expect(RealtimeSubscriber.reconnectDelay(3), const Duration(seconds: 4));
      expect(RealtimeSubscriber.reconnectDelay(4), const Duration(seconds: 8));
      expect(RealtimeSubscriber.reconnectDelay(5), const Duration(seconds: 16));
      expect(RealtimeSubscriber.reconnectDelay(6), const Duration(seconds: 30));
      expect(RealtimeSubscriber.reconnectDelay(7), const Duration(seconds: 30));
      expect(RealtimeSubscriber.reconnectDelay(10), const Duration(seconds: 30));
    });

    test('onError callback is still invoked on each failure (legacy hook)',
        () async {
      final errors = <Object>[];
      subscriber = RealtimeSubscriber(
        server: server,
        onIncomingRow: (row) async => received.add(row),
        onError: errors.add,
        backoffStrategy: (_) => Duration.zero,
      );
      await subscriber.connect(familyId: 'fam-1');
      await Future<void>.delayed(Duration.zero);

      server.realtime.addError(StateError('boom'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
    });
  });
}
