import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Stable per-install device fingerprint used as `written_by_device`
/// on encrypted_rows pushes and as the caregiver-attribution identifier.
///
/// Derived in `main()` from the device-level Ed25519 keypair as
/// `SHA-256(publicKeyBytes)[0:16]` lowercase hex — the same formula used by
/// `supabase/functions/bootstrap_family/index.ts`. RLS in
/// `supabase/migrations/0017_rls_reharden.sql` requires
/// `written_by_device = encode(family_devices.device_fp, 'hex')`, so this
/// value MUST match byte-for-byte with what bootstrap_family stored.
///
/// Throws if not overridden — main.dart must override this with the
/// computed fingerprint before runApp.
final deviceIdProvider = Provider<String>(
  (_) => throw UnimplementedError('Must be overridden in main()'),
);
