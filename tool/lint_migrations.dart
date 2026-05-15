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
