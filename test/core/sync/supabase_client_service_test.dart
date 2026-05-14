import 'package:dreambook/core/sync/supabase_client_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../_fakes/in_memory_secure_storage.dart';

void main() {
  late InMemorySecureStorage storage;

  setUp(() {
    storage = InMemorySecureStorage();
  });

  group('SupabaseClientService', () {
    test('persistJwt() writes JWT under dreambook_supabase_jwt_v1 alias', () async {
      final service = SupabaseClientService.forTest(storage: storage);
      await service.persistJwt('jwt-abc');
      final read = await storage.read(key: 'dreambook_supabase_jwt_v1');
      expect(read, 'jwt-abc');
    });

    test('readJwt() returns persisted value', () async {
      final service = SupabaseClientService.forTest(storage: storage);
      await storage.write(key: 'dreambook_supabase_jwt_v1', value: 'jwt-xyz');
      expect(await service.readJwt(), 'jwt-xyz');
    });

    test('clearJwt() removes persisted entry', () async {
      final service = SupabaseClientService.forTest(storage: storage);
      await service.persistJwt('to-remove');
      await service.clearJwt();
      expect(await service.readJwt(), isNull);
    });
  });
}
