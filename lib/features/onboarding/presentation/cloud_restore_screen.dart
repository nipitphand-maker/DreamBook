import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/crypto/device_identity_service.dart';
import '../../../core/crypto/recovery_code_service.dart';
import '../../../core/families/family_entry.dart';
import '../../../core/families/family_provider.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/providers/shared_preferences_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/sync/snapshot_repository.dart';
import '../../../core/sync/sync_lifecycle_controller.dart';
import '../../../core/theme/design_tokens.dart';
import '../../baby/data/baby_repository.dart';
import '../../baby/data/current_baby_provider.dart';

const _kPhraseBackedUpKey = 'recovery.phrase_backed_up';

const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

class CloudRestoreScreen extends ConsumerStatefulWidget {
  const CloudRestoreScreen({super.key});

  @override
  ConsumerState<CloudRestoreScreen> createState() => _CloudRestoreScreenState();
}

class _CloudRestoreScreenState extends ConsumerState<CloudRestoreScreen> {
  final _controller = TextEditingController();
  bool _restoring = false;
  String? _errorText;

  final _svc = RecoveryCodeService();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final l10n = context.l10n;
    final raw = _controller.text.trim();
    if (raw.isEmpty) return;

    if (!_svc.validateCode(raw)) {
      if (!mounted) return;
      setState(() => _errorText = l10n.recoveryRestoreInvalidChecksum);
      return;
    }

    setState(() {
      _restoring = true;
      _errorText = null;
    });

    try {
      final client = Supabase.instance.client;
      if (client.auth.currentSession == null) {
        await client.auth.signInAnonymously();
      }

      final identity = await DeviceIdentityService(_secureStorage).getOrCreate();
      final normalized = _svc.normalizeCode(raw);
      final lookupHash = await _svc.lookupHash(raw);

      final repo = ref.read(snapshotRepositoryProvider);
      final familyId = await repo.restore(
        lookupHashB64: base64Encode(lookupHash),
        normalizedCode: normalized,
        devicePubKey: identity.publicKeyBytes,
      );

      final prefs = ref.read(sharedPreferencesProvider);
      await ref.read(familyListProvider.notifier).register(FamilyEntry(
        id: familyId,
        label: 'Restored Family',
        createdAt: DateTime.now().toUtc(),
      ));
      await prefs.setBool(_kPhraseBackedUpKey, true);
      await prefs.setBool(kOnboardingDoneKey, true);

      ref.invalidate(syncLifecycleControllerProvider);
      // syncNow doesn't touch the widget tree — fire regardless of mount state.
      unawaited(ref.read(syncLifecycleControllerProvider).syncNow().catchError((_) {}));

      final babies = await ref.read(babyRepositoryProvider).list();
      if (babies.isNotEmpty) {
        await ref.read(currentBabyIdProvider.notifier).select(babies.first.id);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.recoveryRestoreSuccess)),
      );
      context.go(AppRoutes.home);
    } on SnapshotNotFoundError {
      if (!mounted) return;
      setState(() => _errorText = l10n.cloudRestoreNotFound);
    } on SnapshotRateLimitError {
      if (!mounted) return;
      setState(() => _errorText = l10n.cloudRestoreRateLimit);
    } on SnapshotPassphraseError {
      if (!mounted) return;
      setState(() => _errorText = l10n.cloudRestoreWrongPassphrase);
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorText = l10n.cloudRestoreError);
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.cloudRestoreTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.cloudRestoreSubtitle,
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
                enabled: !_restoring,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _restore(),
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
                  child: Text(l10n.cloudRestoreButton),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
