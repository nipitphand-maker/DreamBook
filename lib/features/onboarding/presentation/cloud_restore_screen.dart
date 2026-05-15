import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/crypto/device_identity_service.dart';
import '../../../core/router/app_router.dart';
import '../../../core/sync/snapshot_repository.dart';
import '../../../core/sync/sync_lifecycle_controller.dart';
import '../../../core/theme/design_tokens.dart';

const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

class CloudRestoreScreen extends ConsumerStatefulWidget {
  const CloudRestoreScreen({super.key});

  @override
  ConsumerState<CloudRestoreScreen> createState() => _CloudRestoreScreenState();
}

class _CloudRestoreScreenState extends ConsumerState<CloudRestoreScreen> {
  final _familyIdCtrl = TextEditingController();
  final _passphraseCtrl = TextEditingController();
  bool _obscure = true;
  bool _restoring = false;
  String? _errorText;

  @override
  void dispose() {
    _familyIdCtrl.dispose();
    _passphraseCtrl.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final familyId = _familyIdCtrl.text.trim();
    final passphrase = _passphraseCtrl.text.trim();
    if (familyId.isEmpty || passphrase.isEmpty) return;

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
      final repo = ref.read(snapshotRepositoryProvider);

      await repo.restore(
        familyId: familyId,
        passphrase: passphrase,
        devicePubKey: identity.publicKeyBytes,
      );

      ref.invalidate(syncLifecycleControllerProvider);
      if (!mounted) return;
      await ref.read(syncLifecycleControllerProvider).syncNow().catchError((_) {});
      if (!mounted) return;
      context.go(AppRoutes.home);
    } on SnapshotNotFoundError {
      setState(() => _errorText = 'Family ID not found. Check the ID and try again.');
    } on SnapshotRateLimitError {
      setState(() => _errorText = 'Too many attempts. Wait an hour and try again.');
    } on SnapshotPassphraseError {
      setState(() => _errorText = 'Wrong passphrase. Check and try again.');
    } catch (_) {
      setState(() => _errorText = 'Restore failed. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Restore from cloud backup')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter your Family ID and passphrase to restore your data on this device.',
              style: AppTypography.bodyMedium(
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _familyIdCtrl,
              decoration: const InputDecoration(
                labelText: 'Family ID',
                hintText: 'e.g. XXXX-XXXX',
              ),
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              enabled: !_restoring,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _passphraseCtrl,
              decoration: InputDecoration(
                labelText: 'Passphrase',
                hintText: 'Enter your passphrase',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              obscureText: _obscure,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _restore(),
              autocorrect: false,
              enableSuggestions: false,
              enabled: !_restoring,
            ),
            if (_errorText != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _errorText!,
                style: AppTypography.bodyMedium(color: scheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: _restoring ? null : _restore,
              child: _restoring
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Restore'),
            ),
          ],
        ),
      ),
    );
  }
}
