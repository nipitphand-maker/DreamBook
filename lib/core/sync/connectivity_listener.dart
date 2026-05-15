import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'sync_trigger.dart';

/// Emits [SyncTrigger.networkResume] on connectivity transitions from offline
/// to online. Callers should call [dispose] when done.
class ConnectivityListener {
  ConnectivityListener({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;
  final _controller = StreamController<SyncTrigger>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _wasOffline = false;

  Stream<SyncTrigger> get triggerStream => _controller.stream;

  void start() {
    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (_wasOffline && isOnline) {
        _controller.add(SyncTrigger.networkResume);
      }
      _wasOffline = !isOnline;
    });
  }

  void dispose() {
    _sub?.cancel();
    _controller.close();
  }
}
