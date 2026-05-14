import 'package:dreambook/core/env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Env', () {
    test('parses .env content into supabaseUrl + supabaseAnonKey', () {
      const sample = '''
# comment line
SUPABASE_URL=https://abc.supabase.co
SUPABASE_ANON_KEY=anon-key-123
''';
      final env = Env.fromString(sample);
      expect(env.supabaseUrl, 'https://abc.supabase.co');
      expect(env.supabaseAnonKey, 'anon-key-123');
    });

    test('throws on missing SUPABASE_URL', () {
      expect(
        () => Env.fromString('SUPABASE_ANON_KEY=x\n'),
        throwsA(isA<EnvMissingException>()),
      );
    });

    test('strips surrounding quotes from values', () {
      final env = Env.fromString('SUPABASE_URL="https://x"\nSUPABASE_ANON_KEY=\'k\'\n');
      expect(env.supabaseUrl, 'https://x');
      expect(env.supabaseAnonKey, 'k');
    });
  });
}
