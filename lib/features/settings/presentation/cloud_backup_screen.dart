import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/core/router/app_router.dart';
import 'package:dreambook/core/sync/snapshot_repository.dart';
import 'package:dreambook/core/sync/sync_constants.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';

const _kLastBackupAtKey = 'snapshot.last_backup_at';

class CloudBackupScreen extends ConsumerStatefulWidget {
  const CloudBackupScreen({super.key});

  @override
  ConsumerState<CloudBackupScreen> createState() => _CloudBackupScreenState();
}

class _CloudBackupScreenState extends ConsumerState<CloudBackupScreen> {
  bool _busy = false;

  String? _lastBackupAt() {
    final prefs = ref.read(sharedPreferencesProvider);
    return prefs.getString(_kLastBackupAtKey);
  }

  Future<void> _triggerBackup() async {
    final l10n = context.l10n;
    final prefs = ref.read(sharedPreferencesProvider);
    final familyId = prefs.getString(kFamilyIdPrefsKey);
    if (familyId == null) {
      _showSnack(l10n.cloudBackupNoFamily);
      return;
    }

    const secureStorage = FlutterSecureStorage();
    final code = await secureStorage.read(key: 'recovery.code');
    if (!mounted) return;
    if (code == null) {
      _showSnack(l10n.cloudBackupNoRecoveryCode);
      // Navigate to recovery setup so user can generate their code
      context.push(AppRoutes.bip39Setup);
      return;
    }

    setState(() => _busy = true);
    try {
      final repo = ref.read(snapshotRepositoryProvider);
      await repo.upload(familyId: familyId, passphrase: code);
      if (!mounted) return;
      await prefs.setString(
        _kLastBackupAtKey,
        DateTime.now().toUtc().toIso8601String(),
      );
      await prefs.setString('snapshot.family_id', familyId);
      setState(() {});
      _showSnack(l10n.cloudBackupSuccess);
    } on SnapshotRateLimitError {
      if (!mounted) return;
      _showSnack(l10n.cloudBackupRateLimit);
    } on Exception {
      if (!mounted) return;
      _showSnack(l10n.cloudBackupError);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lastAt = _lastBackupAt();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.cloudBackupTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.cloudBackupStatusTitle,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    lastAt == null
                        ? l10n.cloudBackupNever
                        : l10n.cloudBackupLastAt(lastAt),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: _busy ? null : _triggerBackup,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(l10n.cloudBackupNow),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.cloudBackupHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}
