import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/core/sync/snapshot_repository.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/core/widgets/premium_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final prefs = ref.read(sharedPreferencesProvider);
    final familyId = prefs.getString('family.id');
    if (familyId == null) {
      _showSnack('No family set up yet. Set up sharing first.');
      return;
    }

    final passphrase = await _showPassphraseDialog();
    if (passphrase == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final repo = ref.read(snapshotRepositoryProvider);
      await repo.upload(familyId: familyId, passphrase: passphrase);
      if (!mounted) return;
      await prefs.setString(
        _kLastBackupAtKey,
        DateTime.now().toUtc().toIso8601String(),
      );
      await prefs.setString('snapshot.family_id', familyId);
      setState(() {});
      _showSnack('Backup complete.');
    } on SnapshotRateLimitError {
      if (!mounted) return;
      _showSnack('Too many backup attempts. Please wait and try again.');
    } on Exception {
      if (!mounted) return;
      _showSnack('Backup failed. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _showPassphraseDialog() => showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _PassphraseDialog(),
      );

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final lastAt = _lastBackupAt();

    return Scaffold(
      appBar: AppBar(title: const Text('Cloud Backup')),
      body: PremiumGate(
        lockedChild: const _LockedBody(),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Backup status',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      lastAt == null
                          ? 'Never backed up'
                          : 'Last backed up: $lastAt',
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
              label: const Text('Back up now'),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Creates an encrypted snapshot of your family data. '
              'You will need your passphrase to restore it.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LockedBody extends StatelessWidget {
  const _LockedBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.l10n.premiumLabel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Cloud backup is a Premium feature. Upgrade to protect your family data.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _PassphraseDialog extends StatefulWidget {
  const _PassphraseDialog();

  @override
  State<_PassphraseDialog> createState() => _PassphraseDialogState();
}

class _PassphraseDialogState extends State<_PassphraseDialog> {
  final _ctrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: const Text('Enter backup passphrase'),
      content: TextField(
        controller: _ctrl,
        obscureText: _obscure,
        autofocus: true,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: 'At least 8 characters',
          suffixIcon: IconButton(
            icon: Icon(
              _obscure
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(l10n.actionConfirm),
        ),
      ],
    );
  }

  void _submit() {
    final pass = _ctrl.text;
    if (pass.length < 8) return;
    Navigator.of(context).pop(pass);
  }
}
