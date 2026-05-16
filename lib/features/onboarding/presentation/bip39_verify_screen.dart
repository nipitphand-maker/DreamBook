import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/crypto/family_key_service.dart';
import '../../../core/crypto/recovery_code_service.dart';
import '../../../core/crypto/recovery_service.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/providers/shared_preferences_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/sync/snapshot_repository.dart';
import '../../../core/sync/sync_constants.dart';
import '../../../core/sync/sync_lifecycle_controller.dart';
import '../../../core/theme/design_tokens.dart';

const _kPhraseBackedUpKey = 'recovery.phrase_backed_up';

const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

class Bip39VerifyScreen extends ConsumerStatefulWidget {
  const Bip39VerifyScreen({super.key, required this.phrase});
  final String phrase; // raw 20-char code (no dashes)

  @override
  ConsumerState<Bip39VerifyScreen> createState() => _Bip39VerifyScreenState();
}

class _Bip39VerifyScreenState extends ConsumerState<Bip39VerifyScreen> {
  final _controller = TextEditingController();
  final _svc = RecoveryCodeService();
  final _recovery = RecoveryService();

  int _failCount = 0;
  bool _uploading = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final entered = _svc.normalizeCode(_controller.text);
    final expected = _svc.normalizeCode(widget.phrase);

    if (entered != expected) {
      _failCount++;
      if (_failCount >= 2) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.recoveryVerifyWrongRegenerate)),
        );
        context.pop();
        return;
      }
      setState(() => _errorText = context.l10n.recoveryVerifyWrongTryAgain);
      return;
    }

    setState(() {
      _uploading = true;
      _errorText = null;
    });

    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final familyId = prefs.getString(kFamilyIdPrefsKey) ?? '';
      final familyKey = await FamilyKeyService(_secureStorage).read(familyId: familyId);
      if (familyKey == null) throw Exception('K_family not found');

      final normalized = _svc.normalizeCode(widget.phrase);
      final lookupHash = await _svc.lookupHash(widget.phrase);
      final wrapped = await _recovery.wrapFamilyKey(
        normalizedPhrase: normalized,
        familyKey: familyKey.bytes,
        familyId: familyId,
        keyVersion: familyKey.keyVersion,
      );

      final supa = Supabase.instance.client;
      final resp = await supa.functions.invoke(
        'upload_recovery',
        body: {
          'lookup_hash_b64': base64Encode(lookupHash),
          'wrapped_key_b64': base64Encode(wrapped.wrappedKey),
          'salt_b64': base64Encode(wrapped.salt),
          'key_version': familyKey.keyVersion,
        },
      );
      if (resp.status != 200) throw Exception('upload_recovery failed: ${resp.status}');

      await _secureStorage.write(key: 'recovery.code', value: normalized);

      unawaited(ref.read(snapshotRepositoryProvider).upload(
        familyId: familyId,
        passphrase: normalized,
      ).catchError((_) => 0));

      await prefs.setBool(_kPhraseBackedUpKey, true);
      await prefs.setBool(kOnboardingDoneKey, true);

      ref.invalidate(syncLifecycleControllerProvider);
      ref.read(syncLifecycleControllerProvider).syncNow().ignore();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.recoveryVerifySuccess)),
      );

      final pendingDeepLink = prefs.getString('router.pendingDeepLink');
      if (pendingDeepLink != null && pendingDeepLink.isNotEmpty) {
        await prefs.remove('router.pendingDeepLink');
        if (!mounted) return;
        context.go(pendingDeepLink);
        return;
      }
      context.go(AppRoutes.home);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.push(AppRoutes.feedNew);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = e.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(l10n.recoveryVerifyHeadline),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.recoveryVerifySubcopy,
                style: AppTypography.bodyMedium(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _controller,
                decoration: InputDecoration(
                  labelText: l10n.recoveryVerifyCodeLabel,
                  hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX',
                ),
                autocorrect: false,
                enableSuggestions: false,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _confirm(),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_errorText != null) ...[
                Text(
                  _errorText!,
                  style: AppTypography.bodyMedium(color: scheme.error),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (_uploading)
                const Center(child: CircularProgressIndicator())
              else
                FilledButton(
                  onPressed: _confirm,
                  child: Text(l10n.recoveryVerifyConfirmCta),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
