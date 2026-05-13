import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stable per-install identifier used for caregiver attribution.
///
/// Generated + persisted in `main()` on first launch (SharedPreferences key
/// `device.id`). Plan C uses this for the invite handshake.
///
/// Throws if not overridden — main.dart must override this with the loaded
/// device id before runApp.
final deviceIdProvider = Provider<String>(
  (_) => throw UnimplementedError('Must be overridden in main()'),
);
