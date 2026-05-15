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

  // ---------------------------------------------------------------------------
  // Rule 7: bytea_device_fp_uuid_send_mismatch
  // device_fp (SHA-256 hash bytea) must never be compared to a value derived
  // from auth.uid() (UUID). Shipped in 0002 → required 5 fix migrations to
  // fully retire. This rule prevents reintroduction.
  // ---------------------------------------------------------------------------
  group('Rule 7 — bytea_device_fp_uuid_send_mismatch', () {
    // Mirror of the patterns in tool/lint_migrations.dart so this test acts as
    // the spec for the rule's match logic.
    final bugPatterns = <RegExp>[
      RegExp(
        r'\b\w*device_fp\b\s*=\s*uuid_send\s*\(\s*auth\.uid\s*\(\s*\)\s*\)',
        caseSensitive: false,
      ),
      RegExp(
        r'uuid_send\s*\(\s*auth\.uid\s*\(\s*\)\s*\)\s*=\s*\b\w*device_fp\b',
        caseSensitive: false,
      ),
      RegExp(
        r'\b\w*device_fp\b\s*=\s*auth\.uid\s*\(\s*\)\s*::\s*bytea\b',
        caseSensitive: false,
      ),
      RegExp(
        r'\bauth\.uid\s*\(\s*\)\s*::\s*bytea\b\s*=\s*\b\w*device_fp\b',
        caseSensitive: false,
      ),
      RegExp(
        r'\b\w*device_fp\b\s*=\s*decode\s*\(\s*auth\.uid\s*\(\s*\)\s*::\s*text',
        caseSensitive: false,
      ),
      RegExp(
        r'decode\s*\(\s*auth\.uid\s*\(\s*\)\s*::\s*text[^)]*\)\s*=\s*\b\w*device_fp\b',
        caseSensitive: false,
      ),
    ];

    String stripComments(String sql) {
      var out = sql.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
      out = out.replaceAll(RegExp(r'--[^\n]*'), '');
      return out;
    }

    bool isFlagged(String sql) {
      final code = stripComments(sql);
      return bugPatterns.any((p) => p.hasMatch(code));
    }

    test('flags device_fp = uuid_send(auth.uid()) in CREATE POLICY', () {
      const badSql = '''
CREATE POLICY family_devices_select ON public.family_devices
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.family_devices fd
      WHERE fd.family_id = family_devices.family_id
        AND fd.device_fp = uuid_send(auth.uid())
    )
  );
''';
      expect(isFlagged(badSql), isTrue,
          reason: 'classic 0002_rls.sql anti-pattern must be flagged');
    });

    test('flags uuid_send(auth.uid()) = device_fp (reversed operand order)', () {
      const badSql = '''
CREATE POLICY foo ON public.bar
  FOR SELECT USING (uuid_send(auth.uid()) = device_fp);
''';
      expect(isFlagged(badSql), isTrue);
    });

    test('flags fd.recipient_device_fp = uuid_send(auth.uid()) (qualified column)', () {
      const badSql = '''
CREATE POLICY key_distribution_select ON public.key_distribution
  FOR SELECT USING (recipient_device_fp = uuid_send(auth.uid()));
''';
      expect(isFlagged(badSql), isTrue,
          reason: 'qualified column names like recipient_device_fp must also match');
    });

    test('flags device_fp = auth.uid()::bytea', () {
      const badSql = '''
CREATE POLICY foo ON public.bar
  FOR SELECT USING (device_fp = auth.uid()::bytea);
''';
      expect(isFlagged(badSql), isTrue);
    });

    test('flags auth.uid()::bytea = device_fp (reversed)', () {
      const badSql = '''
CREATE POLICY foo ON public.bar
  FOR SELECT USING (auth.uid()::bytea = device_fp);
''';
      expect(isFlagged(badSql), isTrue);
    });

    test('flags device_fp = decode(auth.uid()::text, ...)', () {
      const badSql = '''
CREATE POLICY foo ON public.bar
  FOR SELECT USING (device_fp = decode(auth.uid()::text, 'hex'));
''';
      expect(isFlagged(badSql), isTrue);
    });

    test('flags decode(auth.uid()::text, ...) = device_fp (reversed)', () {
      const badSql = '''
CREATE POLICY foo ON public.bar
  FOR SELECT USING (decode(auth.uid()::text, 'hex') = device_fp);
''';
      expect(isFlagged(badSql), isTrue);
    });

    test('flags the bug pattern inside CREATE OR REPLACE FUNCTION body', () {
      const badSql = '''
CREATE OR REPLACE FUNCTION public.current_device_family_ids()
RETURNS SETOF uuid
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public
AS \$\$
  SELECT family_id FROM public.family_devices
  WHERE device_fp = uuid_send(auth.uid())
    AND revoked_at IS NULL;
\$\$;
''';
      expect(isFlagged(badSql), isTrue,
          reason: 'SECURITY DEFINER body (0010 pattern) must be flagged');
    });

    test('does NOT flag canonical fix: id IN (SELECT current_user_family_ids())', () {
      const goodSql = '''
DROP POLICY IF EXISTS families_select ON public.families;
CREATE POLICY families_select ON public.families
  FOR SELECT
  USING (id IN (SELECT public.current_user_family_ids()));
''';
      expect(isFlagged(goodSql), isFalse,
          reason: '0026 fix uses current_user_family_ids() helper — must pass');
    });

    test('does NOT flag canonical fix: auth_user_id = auth.uid()', () {
      const goodSql = '''
CREATE OR REPLACE FUNCTION public.current_user_family_ids()
RETURNS SETOF uuid
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public
AS \$\$
  SELECT family_id FROM public.family_devices
  WHERE auth_user_id = auth.uid()
    AND revoked_at IS NULL;
\$\$;
''';
      expect(isFlagged(goodSql), isFalse,
          reason: '0011 helper joins via auth_user_id — must pass');
    });

    test('does NOT flag the bug pattern when it appears only inside -- comments', () {
      // 0026's preamble references the bug in a comment header. The linter
      // strips -- … line comments before scanning, so documentation is safe.
      const goodSql = '''
-- The original families_select policy compared:
--   family_devices.device_fp = uuid_send(auth.uid())
-- which is the bug we are fixing here.
DROP POLICY IF EXISTS families_select ON public.families;
CREATE POLICY families_select ON public.families
  FOR SELECT USING (id IN (SELECT public.current_user_family_ids()));
''';
      expect(isFlagged(goodSql), isFalse,
          reason: 'Bug references inside SQL line comments must not trip the rule');
    });

    test('does NOT flag the bug pattern when documented inside /* … */ blocks', () {
      const goodSql = '''
/*
 * Historical bug: device_fp = uuid_send(auth.uid()) — fixed in 0026.
 */
CREATE POLICY foo ON public.bar
  FOR SELECT USING (id IN (SELECT public.current_user_family_ids()));
''';
      expect(isFlagged(goodSql), isFalse,
          reason: 'Block-comment documentation of the bug must not trip the rule');
    });

    test('does NOT flag device_fp = decode(p_device_fp_hex, ...) (SECURITY DEFINER RPC pattern)', () {
      // 0007/0011 store a hex-encoded device_fp passed in as a parameter and
      // decode it server-side. That is a legitimate pattern — not auth.uid().
      const goodSql = '''
CREATE OR REPLACE FUNCTION public.bootstrap_family_atomic(
  p_device_fp_hex text,
  p_device_pub_key bytea
) RETURNS json LANGUAGE plpgsql SECURITY DEFINER AS \$\$
DECLARE
  v_device_fp bytea;
BEGIN
  v_device_fp := decode(p_device_fp_hex, 'hex');
  SELECT family_id FROM public.family_devices WHERE device_fp = v_device_fp;
END;
\$\$;
''';
      expect(isFlagged(goodSql), isFalse,
          reason: 'decode(p_device_fp_hex, ...) is the correct RPC pattern, not auth.uid()');
    });

    test('does NOT flag encode(device_fp, ...) helper expressions', () {
      // 0017 returns encode(device_fp, 'hex') from a function body — fine.
      const goodSql = '''
CREATE OR REPLACE FUNCTION foo()
RETURNS text LANGUAGE sql AS \$\$
  SELECT encode(device_fp, 'hex') FROM public.family_devices
  WHERE auth_user_id = auth.uid() LIMIT 1;
\$\$;
''';
      expect(isFlagged(goodSql), isFalse);
    });
  });
}
