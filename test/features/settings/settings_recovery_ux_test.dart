// test/features/settings/settings_recovery_ux_test.dart
//
// Recovery-UX 2026-05-16 regression guard for SettingsScreen.
//
// NOTE — why this is a SOURCE-LEVEL test, not a `pumpWidget` widget test:
//
// `SettingsScreen` transitively imports `lib/core/router/app_router.dart`
// for the `AppRoutes` URL constants. `app_router.dart` in turn imports
// every routed screen — including `lib/features/home/presentation/
// home_screen.dart`, which currently has a pre-existing compile error
// (calls `AppTypography.titleMedium` — that getter doesn't exist on
// `AppTypography`). The error is invisible to `flutter analyze` (it only
// shows up during kernel compilation), but it makes any `flutter test`
// that loads `SettingsScreen` fail to compile. `home_screen.dart` is
// owned by another team and we are explicitly forbidden from touching
// it, so we can't `pumpWidget(SettingsScreen())` in a test.
//
// Instead, this test reads `settings_screen.dart` as source and pins the
// IA invariants by string match. It still fires on the regression we
// care about: any future contributor who promotes BIP39 back to the
// top-level Security tile, or who removes Cloud Backup from the same,
// will break this test.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SettingsScreen recovery UX (source-level)', () {
    late String src;

    setUpAll(() async {
      src = await File(
        'lib/features/settings/presentation/settings_screen.dart',
      ).readAsString();
    });

    test('Cloud Backup tile uses the new recoveryUxCloudBackupTitle key', () {
      expect(
        src.contains('recoveryUxCloudBackupTitle'),
        isTrue,
        reason:
            'Settings → Security must render the Cloud Backup tile with the '
            'recoveryUxCloudBackupTitle ARB key — that\'s the canonical '
            'primary-recovery copy after the 2026-05-16 demotion.',
      );
      expect(
        src.contains('AppRoutes.cloudBackup'),
        isTrue,
        reason:
            'The Cloud Backup tile must point at AppRoutes.cloudBackup so '
            'parents reach the backup screen in one tap from Settings root.',
      );
    });

    test('Recovery phrase tile lives under the Advanced section header', () {
      // Ordering check: the Advanced section header must appear BEFORE the
      // BIP39 setup entry, and AFTER the Cloud Backup tile. This pins the
      // IA invariant that BIP39 has been demoted.
      final advancedIdx = src.indexOf('recoveryUxAdvancedSectionTitle');
      final cloudIdx = src.indexOf('recoveryUxCloudBackupTitle');
      final bip39Idx = src.indexOf('AppRoutes.bip39Setup');

      expect(advancedIdx, isNonNegative,
          reason: 'Advanced section header must be present in Settings.');
      expect(cloudIdx, isNonNegative,
          reason: 'Cloud Backup tile must be present in Settings.');
      expect(bip39Idx, isNonNegative,
          reason:
              'BIP39 setup entry must still be reachable from Settings — '
              'demoted, not deleted.');

      expect(
        cloudIdx < advancedIdx,
        isTrue,
        reason:
            'Cloud Backup tile must appear BEFORE the Advanced section '
            'header — Cloud Backup is the recommended path, the seed '
            'phrase sits underneath.',
      );
      expect(
        advancedIdx < bip39Idx,
        isTrue,
        reason:
            'BIP39 setup entry must sit BELOW the Advanced section header '
            '— a future contributor who hoists it back to top-level '
            'Security has just shipped the bug we tried to fix.',
      );
    });

    test('BIP39 tile uses the demoted "(advanced)" ARB key', () {
      expect(
        src.contains('recoveryUxAdvancedRecoveryPhraseTitle'),
        isTrue,
        reason:
            'The BIP39 tile must render the recoveryUxAdvancedRecoveryPhrase'
            'Title key — that copy reads "Recovery phrase (advanced)" so '
            'parents understand it is not the recommended option.',
      );
      expect(
        src.contains('settingsRecoveryPhraseTitle'),
        isFalse,
        reason:
            'The old top-level settingsRecoveryPhraseTitle key must no '
            'longer be wired into Settings — it was the symbol of the '
            'pre-demotion IA. Use recoveryUxAdvancedRecoveryPhraseTitle.',
      );
    });
  });
}
