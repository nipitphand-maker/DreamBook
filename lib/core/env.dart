/// Loads `.env` content into typed configuration.
///
/// In production, [Env.load] reads the bundled `.env` asset (declared in
/// pubspec) at app start. Tests inject content via [Env.fromString].
class Env {
  const Env({
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    this.sentryDsn,
  });

  final String supabaseUrl;
  final String supabaseAnonKey;

  /// Optional Sentry DSN for opt-in crash reporting. Null when not configured.
  final String? sentryDsn;

  /// Parses .env-style content. Lines starting with `#` are ignored.
  /// Values may be wrapped in single or double quotes (stripped on parse).
  factory Env.fromString(String content) {
    final map = <String, String>{};
    for (final raw in content.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final eq = line.indexOf('=');
      if (eq < 0) continue;
      final key = line.substring(0, eq).trim();
      var value = line.substring(eq + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
           (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      map[key] = value;
    }
    final url = map['SUPABASE_URL'];
    final key = map['SUPABASE_ANON_KEY'];
    if (url == null || url.isEmpty) {
      throw const EnvMissingException('SUPABASE_URL');
    }
    if (key == null || key.isEmpty) {
      throw const EnvMissingException('SUPABASE_ANON_KEY');
    }
    final sentryDsn = map['SENTRY_DSN'];
    return Env(
      supabaseUrl: url,
      supabaseAnonKey: key,
      sentryDsn: sentryDsn?.isEmpty == true ? null : sentryDsn,
    );
  }
}

class EnvMissingException implements Exception {
  const EnvMissingException(this.varName);
  final String varName;
  @override
  String toString() => 'EnvMissingException: $varName is missing from .env';
}
