// Schema diff tool — runs supabase db diff and exits non-zero on drift.
// Usage: dart run tool/schema_diff.dart [--db-url <staging-url>]
// Requires supabase CLI and STAGING_SUPABASE_URL env var (set in CI secrets).
//
// In local development this script is a no-op when STAGING_SUPABASE_URL is
// unset — it exits 0 so the rest of the dev workflow is not blocked.

import 'dart:io';

Future<void> main(List<String> args) async {
  final stagingUrl = Platform.environment['STAGING_SUPABASE_URL'];
  if (stagingUrl == null || stagingUrl.isEmpty) {
    stdout.writeln(
      'schema_diff: STAGING_SUPABASE_URL not set — '
      'skipping diff (OK in local dev)',
    );
    exitCode = 0;
    return;
  }

  stdout.writeln('Running schema diff against staging...');
  final result = await Process.run(
    'supabase',
    ['db', 'diff', '--linked', '--schema', 'public'],
    environment: {
      ...Platform.environment,
      'SUPABASE_DB_URL': stagingUrl,
    },
  );

  final processStdout = result.stdout as String;
  final processStderr = result.stderr as String;

  if (result.exitCode != 0) {
    stdout.writeln('ERROR: supabase db diff failed:\n$processStderr');
    exitCode = 1;
    return;
  }

  final drift = processStdout.trim();
  if (drift.isEmpty) {
    stdout.writeln(
      'schema_diff: No drift detected. Staging matches production schema.',
    );
    exitCode = 0;
  } else {
    stdout.writeln('ERROR: Schema drift detected between staging and production:');
    stdout.writeln(drift);
    exitCode = 1;
  }
}
