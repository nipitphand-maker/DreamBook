/// Minimal fake of FlutterSecureStorage used by Plan C-1 service tests.
///
/// Satisfies: read, write, delete, deleteAll, containsKey. Does NOT
/// implement: readAll, ios/android options. Tests override real storage
/// with this fake via constructor injection on each service.
class InMemorySecureStorage {
  final Map<String, String> _store = {};
  bool simulateReadCorruption = false;

  Future<String?> read({required String key}) async {
    if (simulateReadCorruption) {
      throw const _FakeStorageCorruption();
    }
    return _store[key];
  }

  Future<void> write({required String key, required String value}) async {
    _store[key] = value;
  }

  Future<void> delete({required String key}) async {
    _store.remove(key);
  }

  Future<void> deleteAll() async {
    _store.clear();
  }

  Future<bool> containsKey({required String key}) async {
    return _store.containsKey(key);
  }

  /// Test-only inspection.
  Map<String, String> get snapshot => Map.unmodifiable(_store);
}

class _FakeStorageCorruption implements Exception {
  const _FakeStorageCorruption();
}
