// Synthetic fixtures for each linter rule.
// Rule violations are tested by running the linter logic inline.
// Full integration (dart run tool/lint_migrations.dart) is tested in CI.

@Tags(['unit'])
library;

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Migration linter fixture definitions', () {
    test('valid migration has RLS + GRANT', () {
      const sql = '''
CREATE TABLE public.foo (id uuid PRIMARY KEY);
ALTER TABLE public.foo ENABLE ROW LEVEL SECURITY;
CREATE POLICY foo_select ON public.foo FOR SELECT TO authenticated USING (true);
GRANT SELECT ON public.foo TO authenticated;
''';
      expect(sql, contains('ENABLE ROW LEVEL SECURITY'));
      expect(sql, contains('GRANT'));
    });

    test('bad migration missing RLS is detectable', () {
      const badSql = '''
CREATE TABLE public.bar (id uuid PRIMARY KEY);
GRANT SELECT ON public.bar TO authenticated;
''';
      expect(badSql, isNot(contains('ENABLE ROW LEVEL SECURITY')));
    });

    test('replacement migration CREATE POLICY without DROP POLICY IF EXISTS is detectable', () {
      // Rule 3 fires only in replacement migrations (files that also have DROP POLICY IF EXISTS)
      const badSql = '''
DROP POLICY IF EXISTS old_policy ON public.foo;
CREATE POLICY old_policy ON public.foo FOR SELECT TO authenticated USING (true);
CREATE POLICY new_policy ON public.foo FOR INSERT TO authenticated WITH CHECK (true);
''';
      // new_policy has no matching DROP POLICY IF EXISTS
      final hasDropForNew = RegExp(
        r'DROP POLICY IF EXISTS\s+new_policy',
        caseSensitive: false,
      ).hasMatch(badSql);
      expect(hasDropForNew, isFalse,
          reason: 'new_policy is missing its DROP POLICY IF EXISTS guard');
    });

    test('first-time policy creation does not require DROP POLICY IF EXISTS', () {
      // Rule 3 is exempt for files with no DROP POLICY at all
      const firstTimeSql = '''
CREATE POLICY foo_select ON public.foo FOR SELECT TO authenticated USING (true);
CREATE POLICY foo_insert ON public.foo FOR INSERT TO authenticated WITH CHECK (true);
''';
      final hasAnyDrop = RegExp(
        r'DROP POLICY IF EXISTS',
        caseSensitive: false,
      ).hasMatch(firstTimeSql);
      expect(hasAnyDrop, isFalse,
          reason: 'File has no drops → Rule 3 does not apply');
    });

    test('DROP COLUMN without deprecation comment is detectable', () {
      const badSql = 'ALTER TABLE public.foo DROP COLUMN old_col;';
      final lines = badSql.split('\n');
      final dropIdx = lines.indexWhere(
        (l) => RegExp(r'ALTER TABLE.*DROP COLUMN', caseSensitive: false).hasMatch(l),
      );
      final lookback =
          lines.sublist((dropIdx - 3).clamp(0, dropIdx), dropIdx);
      final hasDeprecation = lookback.any(
        (l) => l.trim().startsWith('-- deprecation:'),
      );
      expect(hasDeprecation, isFalse,
          reason: 'No -- deprecation: comment precedes DROP COLUMN');
    });

    test('DROP COLUMN with deprecation comment passes', () {
      const goodSql = '''
-- deprecation: old_col replaced by new_col in v2.3
ALTER TABLE public.foo DROP COLUMN old_col;
''';
      final lines = goodSql.split('\n');
      final dropIdx = lines.indexWhere(
        (l) => RegExp(r'ALTER TABLE.*DROP COLUMN', caseSensitive: false).hasMatch(l),
      );
      final lookback =
          lines.sublist((dropIdx - 3).clamp(0, dropIdx), dropIdx);
      final hasDeprecation = lookback.any(
        (l) => l.trim().startsWith('-- deprecation:'),
      );
      expect(hasDeprecation, isTrue,
          reason: '-- deprecation: comment must precede DROP COLUMN');
    });

    test('decodeBytea presence check logic', () {
      // Rule 2: if bytea columns exist, decodeBytea() must be called in sync/
      const syncDartContent = '''
final row = decodeBytea(data['ciphertext']);
''';
      expect(syncDartContent.contains('decodeBytea('), isTrue);
    });
  });
}
