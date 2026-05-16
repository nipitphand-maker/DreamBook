import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/crypto/device_identity_service.dart';
import '../../../core/crypto/recovery_code_service.dart';
import '../../../core/crypto/family_key_service.dart';
import '../../../core/crypto/recovery_service.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/providers/shared_preferences_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/sync/snapshot_repository.dart';
import '../../../core/sync/sync_constants.dart';
import '../../../core/sync/sync_lifecycle_controller.dart';
import '../../../core/theme/design_tokens.dart';
import '../../baby/data/baby_repository.dart';
import '../../baby/data/current_baby_provider.dart';
import '../../../core/families/family_entry.dart';
import '../../../core/families/family_provider.dart';

const _kPhraseBackedUpKey = 'recovery.phrase_backed_up';

const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

class Bip39RestoreScreen extends ConsumerStatefulWidget {
  const Bip39RestoreScreen({super.key});

  @override
  ConsumerState<Bip39RestoreScreen> createState() => _Bip39RestoreScreenState();
}

class _Bip39RestoreScreenState extends ConsumerState<Bip39RestoreScreen> {
  final _controller = TextEditingController();
  bool _restoring = false;
  String? _errorText;

  final _svc = RecoveryCodeService();
  final _recovery = RecoveryService();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return;

    final l10nLocal = context.l10n;
    if (!_svc.validateCode(raw)) {
      if (!mounted) return;
      setState(() => _errorText = l10nLocal.recoveryRestoreInvalidChecksum);
      return;
    }

    setState(() {
      _restoring = true;
      _errorText = null;
    });

    try {
      final supa = Supabase.instance.client;
      if (supa.auth.currentSession == null) {
        await supa.auth.signInAnonymously();
      }

      final identity = await DeviceIdentityService(_secureStorage).getOrCreate();
      final normalized = _svc.normalizeCode(raw);
      final lookupHash = await _svc.lookupHash(raw);

      final resp = await supa.functions.invoke(
        'claim_recovery',
        body: {
          'lookup_hash_b64': base64Encode(lookupHash),
          'device_pub_key_b64': base64Encode(identity.publicKeyBytes),
        },
      );

      if (resp.status == 404) {
        // Try snapshot fallback before giving up
        try {
          final repo = ref.read(snapshotRepositoryProvider);
          final familyId = await repo.restore(
            lookupHashB64: base64Encode(lookupHash),
            normalizedCode: normalized,
            devicePubKey: identity.publicKeyBytes,
          );
          // Post-restore setup (same as below but without FamilyKeyService.install — already done by repo)
          final prefs = ref.read(sharedPreferencesProvider);
          await ref.read(familyListProvider.notifier).register(FamilyEntry(
            id: familyId,
            label: 'Restored Family',
            createdAt: DateTime.now().toUtc(),
          ));
          await prefs.setBool(_kPhraseBackedUpKey, true);
          await prefs.setBool(kOnboardingDoneKey, true);
          ref.invalidate(syncLifecycleControllerProvider);
          if (!mounted) return;
          await ref.read(syncLifecycleControllerProvider).syncNow();
          final babies = await ref.read(babyRepositoryProvider).list();
          if (babies.isNotEmpty) {
            await ref.read(currentBabyIdProvider.notifier).select(babies.first.id);
          }
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.recoveryRestoreSuccess)),
          );
          context.go(AppRoutes.home);
          return;
        } on SnapshotPassphraseError catch (_) {
          rethrow; // let outer catch handle with passphrase-specific message
        } catch (_) {
          throw Exception(l10nLocal.recoveryRestoreNotFound); // keep for actual 404
        }
      }
      if (resp.status == 429) {
        throw Exception(l10nLocal.recoveryRestoreRateLimit);
      }
      if (resp.status != 200) {
        throw Exception(l10nLocal.recoveryRestoreError);
      }

      final data = resp.data as Map<String, dynamic>;
      final wrappedKey = base64Decode(
        (data['wrapped_key_b64'] as String).replaceAll('\n', '').replaceAll('\r', ''),
      );
      final salt = base64Decode(
        (data['salt_b64'] as String).replaceAll('\n', '').replaceAll('\r', ''),
      );
      final familyId = data['family_id'] as String;
      final keyVersion = data['key_version'] as int;

      final familyKeyBytes = await _recovery.unwrapFamilyKey(
        normalizedPhrase: normalized,
        wrappedKey: Uint8List.fromList(wrappedKey),
        salt: Uint8List.fromList(salt),
        familyId: familyId,
        keyVersion: keyVersion,
      );

      await FamilyKeyService(_secureStorage).install(
        familyId: familyId,
        bytes: familyKeyBytes,
        keyVersion: keyVersion,
      );

      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setString(kFamilyIdPrefsKey, familyId);
      await ref.read(familyListProvider.notifier).register(FamilyEntry(
        id: familyId,
        label: 'Restored Family',
        createdAt: DateTime.now().toUtc(),
      ));
      await prefs.setBool(_kPhraseBackedUpKey, true);
      await prefs.setBool(kOnboardingDoneKey, true);

      ref.invalidate(syncLifecycleControllerProvider);

      if (!mounted) return;
      await ref.read(syncLifecycleControllerProvider).syncNow();

      final babies = await ref.read(babyRepositoryProvider).list();
      if (babies.isNotEmpty) {
        await ref.read(currentBabyIdProvider.notifier).select(babies.first.id);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.recoveryRestoreSuccess)),
      );
      context.go(AppRoutes.home);
    } on SnapshotPassphraseError catch (_) {
      if (!mounted) return;
      setState(() => _errorText = context.l10n.cloudRestoreWrongPassphrase);
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = e.toString());
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.recoveryRestoreHeadline)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.recoveryRestoreSubcopy,
                style: AppTypography.bodyMedium(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _controller,
                decoration: InputDecoration(
                  labelText: l10n.recoveryRestoreLabel,
                  hintText: l10n.recoveryRestoreHint,
                ),
                maxLines: 1,
                keyboardType: TextInputType.text,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
              ),
              const SizedBox(height: AppSpacing.md),
              if (_errorText != null) ...[
                Text(
                  _errorText!,
                  style: AppTypography.bodyMedium(color: scheme.error),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (_restoring)
                const Center(child: CircularProgressIndicator())
              else
                FilledButton(
                  onPressed: _restore,
                  child: Text(l10n.recoveryRestoreCta),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
