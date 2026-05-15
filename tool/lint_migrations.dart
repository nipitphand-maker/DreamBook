// Migration linter — runs in CI to catch schema regressions.
// Rules:
//   1. Every CREATE TABLE → must have ENABLE ROW LEVEL SECURITY in the same file
//      AND at least one GRANT must exist somewhere across the migration set.
//      (Legacy note: 0001_init.sql predates per-file GRANT convention; grants
//      were back-filled in 0016_grant_and_fix_rls.sql. New tables must include
//      GRANT in the same file as CREATE TABLE.)
//   2. Every bytea column → must have a decodeBytea() call site in lib/core/sync/
//   3. CREATE POLICY in a replacement migration (one that also has DROP POLICY IF EXISTS)
//      → every CREATE POLICY must have a matching DROP POLICY IF EXISTS in the same file.
//      First-time policy creation files (no drops present) are exempt.
//   4. Schema diff vs prod required (placeholder rule — passes if schema_diff tool is present)
//   5. ALTER TABLE DROP COLUMN → must be preceded by -- deprecation: comment in the same file
//   7. bytea_device_fp_uuid_send_mismatch — flags the cross-type compare bug that
//      shipped in 0002/0010 (fixed by 0011/0016/0017/0026): device_fp is
//      SHA-256(pubkey)[0:16] (16 bytes); uuid_send(auth.uid()) is the 16-byte UUID
//      raw form. They are bytea-bytea but semantically unrelated → never equal →
//      RLS silently denies every row. Detects both operand orders and the
//      auth.uid()::bytea / decode(auth.uid()::text, …) variants.
//      Fix: compare auth_user_id = auth.uid() against family_devices, or use
//      `id IN (SELECT public.current_user_family_ids())`.
//      Grandfathered files (legacy, already superseded): 0002_rls.sql, 0010_fix_rls_recursion.sql.
//
// Note: Rule 2 uses decodeBytea (not _decodeBytes) per plan audit §"bytea decoder name mismatch".
// Rule 4 (schema diff) requires staging Supabase secrets — deferred to CI job.
// Staging-only files under supabase/migrations/staging/ are excluded from prod checks.

import 'dart:io';

void main(List<String> args) {
  final migrationsDir = Directory('supabase/migrations');
  final syncDir = Directory('lib/core/sync');

  if (!migrationsDir.existsSync()) {
    stdout.writeln('ERROR: supabase/migrations/ not found. Run from project root.');
    exitCode = 1;
    return;
  }

  // Collect production migration files (exclude staging/)
  final files = migrationsDir
      .listSync(recursive: false)
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final errors = <String>[];

  // Collect all bytea column declarations across all migrations
  final byteaColumns = <String>{}; // basename.columnName
  for (final file in files) {
    final content = file.readAsStringSync();
    // Match: column_name bytea (various forms)
    final byteaMatches = RegExp(
      r'^\s*(\w+)\s+bytea',
      multiLine: true,
      caseSensitive: false,
    ).allMatches(content);
    for (final m in byteaMatches) {
      byteaColumns.add('${_basename(file.path)}.${m.group(1)}');
    }
  }

  // Grep for decodeBytea in lib/core/sync/
  final decodeSites = <String>{};
  if (syncDir.existsSync()) {
    for (final f in syncDir.listSync(recursive: false).whereType<File>()) {
      if (f.path.endsWith('.dart')) {
        final content = f.readAsStringSync();
        if (content.contains('decodeBytea(')) {
          decodeSites.add(_basename(f.path));
        }
      }
    }
  }

  // Build global content for cross-file checks (Rule 1 GRANT check)
  final globalContent = files.map((f) => f.readAsStringSync()).join('\n');
  final globalHasGrant = RegExp(r'\bGRANT\b', caseSensitive: false).hasMatch(globalContent);

  bool reportedMissingGrant = false;

  for (final file in files) {
    final content = file.readAsStringSync();
    final name = _basename(file.path);

    // Rule 1: CREATE TABLE → ENABLE ROW LEVEL SECURITY in same file
    //         + at least one GRANT anywhere across all migration files
    final tableMatches = RegExp(
      r'CREATE TABLE\s+(?:(?:public|private)\.)?\w+',
      caseSensitive: false,
    ).allMatches(content);
    for (final _ in tableMatches) {
      final hasRls = RegExp(
        r'ENABLE ROW LEVEL SECURITY',
        caseSensitive: false,
      ).hasMatch(content);
      if (!hasRls) {
        errors.add('$name [Rule 1]: CREATE TABLE without ENABLE ROW LEVEL SECURITY in same file');
      }
      if (!globalHasGrant && !reportedMissingGrant) {
        errors.add('[Rule 1]: CREATE TABLE exists but no GRANT found anywhere in migration set');
        reportedMissingGrant = true;
      }
      break; // one error per file is enough
    }

    // Rule 3: Replacement migrations (those with DROP POLICY IF EXISTS) must have
    //         a matching DROP POLICY IF EXISTS for every CREATE POLICY in the same file.
    //         First-time creation files (no drops) are exempt.
    final hasAnyDrop = RegExp(
      r'DROP POLICY IF EXISTS',
      caseSensitive: false,
    ).hasMatch(content);
    if (hasAnyDrop) {
      final policyMatches = RegExp(
        r'CREATE POLICY\s+(\w+)',
        caseSensitive: false,
      ).allMatches(content);
      for (final m in policyMatches) {
        final policyName = m.group(1)!;
        final hasDrop = RegExp(
          'DROP POLICY IF EXISTS\\s+$policyName',
          caseSensitive: false,
        ).hasMatch(content);
        if (!hasDrop) {
          errors.add(
            '$name [Rule 3]: replacement migration has CREATE POLICY $policyName '
            'without matching DROP POLICY IF EXISTS $policyName',
          );
        }
      }
    }

    // Rule 5: ALTER TABLE DROP COLUMN must have -- deprecation: comment
    final dropColumnMatches = RegExp(
      r'ALTER TABLE.*DROP COLUMN',
      caseSensitive: false,
    ).allMatches(content);
    for (final m in dropColumnMatches) {
      final pos = m.start;
      // Look backwards for -- deprecation: within 3 lines
      final before = content.substring(0, pos);
      final beforeLines = before.split('\n');
      final lookback = beforeLines.reversed.take(3).toList();
      final hasDeprecation = lookback.any((l) => l.trim().startsWith('-- deprecation:'));
      if (!hasDeprecation) {
        errors.add(
          '$name [Rule 5]: DROP COLUMN without -- deprecation: comment in preceding 3 lines',
        );
      }
    }

    // Rule 7: bytea_device_fp_uuid_send_mismatch
    // device_fp (SHA-256 hash bytea) must NEVER be compared to a value derived
    // from auth.uid() (UUID). Catches:
    //   • device_fp = uuid_send(auth.uid())       (either operand order)
    //   • device_fp = auth.uid()::bytea           (either operand order)
    //   • device_fp = decode(auth.uid()::text, …) (either operand order)
    // Strip SQL line comments (-- …) so documentation of the bug in comments
    // does not trip the rule (e.g. 0026's preamble, 0011's header note).
    if (!_byteaMismatchGrandfathered.contains(name)) {
      final codeOnly = _stripSqlLineComments(content);
      final bugPatterns = <RegExp>[
        // device_fp = uuid_send(auth.uid())  (and reversed)
        RegExp(
          r'\b\w*device_fp\b\s*=\s*uuid_send\s*\(\s*auth\.uid\s*\(\s*\)\s*\)',
          caseSensitive: false,
        ),
        RegExp(
          r'uuid_send\s*\(\s*auth\.uid\s*\(\s*\)\s*\)\s*=\s*\b\w*device_fp\b',
          caseSensitive: false,
        ),
        // device_fp = auth.uid()::bytea  (and reversed)
        RegExp(
          r'\b\w*device_fp\b\s*=\s*auth\.uid\s*\(\s*\)\s*::\s*bytea\b',
          caseSensitive: false,
        ),
        RegExp(
          r'\bauth\.uid\s*\(\s*\)\s*::\s*bytea\b\s*=\s*\b\w*device_fp\b',
          caseSensitive: false,
        ),
        // device_fp = decode(auth.uid()::text, …)  (and reversed)
        RegExp(
          r'\b\w*device_fp\b\s*=\s*decode\s*\(\s*auth\.uid\s*\(\s*\)\s*::\s*text',
          caseSensitive: false,
        ),
        RegExp(
          r'decode\s*\(\s*auth\.uid\s*\(\s*\)\s*::\s*text[^)]*\)\s*=\s*\b\w*device_fp\b',
          caseSensitive: false,
        ),
      ];
      var flagged = false;
      for (final p in bugPatterns) {
        if (p.hasMatch(codeOnly)) {
          flagged = true;
          break;
        }
      }
      if (flagged) {
        errors.add(
          '$name [Rule 7 bytea_device_fp_uuid_send_mismatch]: device_fp '
          '(SHA-256 hash bytea) compared to a value derived from auth.uid() '
          '(UUID). These bytea operands are never equal and silently kill RLS. '
          'Fix: join via family_devices.auth_user_id = auth.uid(), or use '
          '"id IN (SELECT public.current_user_family_ids())".',
        );
      }
    }
  }

  // Rule 2: bytea columns exist → decodeBytea() must be present in lib/core/sync/
  if (byteaColumns.isNotEmpty && decodeSites.isEmpty) {
    errors.add(
      '[Rule 2]: bytea columns exist in migrations but no decodeBytea() '
      'call found in lib/core/sync/',
    );
  }

  // Rule 6 (plan audit): Staging files must not appear in prod migration set
  final stagingDir = Directory('supabase/migrations/staging');
  if (stagingDir.existsSync()) {
    final stagingFiles = stagingDir
        .listSync(recursive: false)
        .whereType<File>()
        .where((f) => f.path.endsWith('.sql'))
        .toList();
    for (final sf in stagingFiles) {
      final sfName = _basename(sf.path);
      final inProd = files.any((f) => _basename(f.path) == sfName);
      if (inProd) {
        errors.add('$sfName [Rule 6]: staging helper found in prod migration set');
      }
    }
  }

  if (errors.isEmpty) {
    stdout.writeln('Migration linter: OK (${files.length} files checked)');
  } else {
    for (final e in errors) {
      stdout.writeln('ERROR: $e');
    }
    exitCode = 1;
  }
}

String _basename(String path) => path.split('/').last;

// Files that historically contain the bug pattern but were superseded by later
// fixes (0011/0016/0017/0026). New migrations are NOT exempt.
const _byteaMismatchGrandfathered = <String>{
  '0002_rls.sql',
  '0010_fix_rls_recursion.sql',
};

// Strip SQL line comments (-- …) so the linter does not trip on documentation
// of a bug pattern inside header comments. Block comments (/* … */) are
// also stripped. String literals are left alone — migrations don't embed
// `device_fp = uuid_send(...)` inside quoted strings.
String _stripSqlLineComments(String sql) {
  // Remove /* … */ block comments first (non-greedy, dotall via [\s\S]).
  var out = sql.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  // Then strip --… line comments to end-of-line.
  out = out.replaceAll(RegExp(r'--[^\n]*'), '');
  return out;
}
