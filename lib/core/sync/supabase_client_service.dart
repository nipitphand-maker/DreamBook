import 'package:supabase_flutter/supabase_flutter.dart';

import '../env.dart';

/// Owns the Supabase client lifecycle for DreamBook.
///
/// Production: [SupabaseClientService.initialize] is called once from `main()`
/// with the loaded [Env]. After initialise, [client] returns the singleton
/// `Supabase.instance.client`. Anonymous auth runs on first launch and the
/// JWT is mirrored to secure storage so we can read it across cold starts
/// without depending on Supabase's internal session cache.
///
/// Tests use [SupabaseClientService.forTest] which bypasses the real client
/// and lets us drive JWT persistence directly.
class SupabaseClientService {
  SupabaseClientService._(this._storage);

  static SupabaseClientService? _instance;

  /// Visible-for-tests constructor.
  SupabaseClientService.forTest({required dynamic storage}) : _storage = storage;

  final dynamic _storage;

  static const String jwtAlias = 'dreambook_supabase_jwt_v1';

  /// Call once from main() before any sync code runs.
  static Future<SupabaseClientService> initialize({
    required Env env,
    required dynamic storage,
  }) async {
    await Supabase.initialize(
      url: env.supabaseUrl,
      anonKey: env.supabaseAnonKey,
    );
    final svc = SupabaseClientService._(storage);
    Supabase.instance.client.auth.onAuthStateChange.listen((data) async {
      final jwt = data.session?.accessToken;
      if (jwt != null) {
        await svc.persistJwt(jwt);
      }
    });
    _instance = svc;
    return svc;
  }

  static SupabaseClientService get instance {
    final i = _instance;
    if (i == null) {
      throw StateError('SupabaseClientService.initialize() not called yet');
    }
    return i;
  }

  /// Returns the live Supabase client. Throws if [initialize] hasn't run.
  SupabaseClient get client => Supabase.instance.client;

  /// Signs in anonymously if no current session. Idempotent.
  Future<void> ensureAnonymousSession() async {
    final session = client.auth.currentSession;
    if (session != null) return;
    await client.auth.signInAnonymously();
  }

  Future<void> persistJwt(String jwt) async {
    await _storage.write(key: jwtAlias, value: jwt);
  }

  Future<String?> readJwt() async {
    return await _storage.read(key: jwtAlias) as String?;
  }

  Future<void> clearJwt() async {
    await _storage.delete(key: jwtAlias);
  }
}
