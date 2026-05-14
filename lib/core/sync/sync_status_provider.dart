import 'package:flutter_riverpod/flutter_riverpod.dart';

class SyncStatus {
  const SyncStatus({
    this.inFlight = false,
    this.lastSyncedAt,
    this.lastError,
  });

  final bool inFlight;
  final DateTime? lastSyncedAt;
  final Object? lastError;

  SyncStatus copyWith({
    bool? inFlight,
    DateTime? lastSyncedAt,
    Object? lastError,
    bool clearError = false,
  }) =>
      SyncStatus(
        inFlight: inFlight ?? this.inFlight,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

class SyncStatusNotifier extends Notifier<SyncStatus> {
  @override
  SyncStatus build() => const SyncStatus();

  void startSync() {
    state = state.copyWith(inFlight: true, clearError: true);
  }

  void completeSync({required DateTime at}) {
    state = state.copyWith(inFlight: false, lastSyncedAt: at, clearError: true);
  }

  void failSync(Object error) {
    state = state.copyWith(inFlight: false, lastError: error);
  }
}

final syncStatusProvider =
    NotifierProvider<SyncStatusNotifier, SyncStatus>(SyncStatusNotifier.new);
