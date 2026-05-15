import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dreambook/core/sync/connectivity_listener.dart';
import 'package:dreambook/core/sync/sync_trigger.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeConnectivity implements Connectivity {
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      _controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.wifi];

  void emit(List<ConnectivityResult> results) => _controller.add(results);

  void close() => _controller.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('emits networkResume on offline → online transition', () async {
    final fakeConn = FakeConnectivity();
    final listener = ConnectivityListener(connectivity: fakeConn);
    final triggers = <SyncTrigger>[];
    listener.triggerStream.listen(triggers.add);
    listener.start();

    fakeConn.emit([ConnectivityResult.none]); // go offline
    fakeConn.emit([ConnectivityResult.wifi]); // come back online
    await Future<void>.delayed(Duration.zero); // flush microtask queue

    expect(triggers, [SyncTrigger.networkResume]);
    listener.dispose();
    fakeConn.close();
  });

  test('does not emit when already online → online', () async {
    final fakeConn = FakeConnectivity();
    final listener = ConnectivityListener(connectivity: fakeConn);
    final triggers = <SyncTrigger>[];
    listener.triggerStream.listen(triggers.add);
    listener.start();

    fakeConn.emit([ConnectivityResult.wifi]); // already online
    fakeConn.emit([ConnectivityResult.mobile]); // switch to mobile (still online)
    await Future<void>.delayed(Duration.zero);

    expect(triggers, isEmpty);
    listener.dispose();
    fakeConn.close();
  });
}
