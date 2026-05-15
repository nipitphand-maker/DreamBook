import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/crypto/device_identity_service.dart';
import '../../../core/crypto/family_key_service.dart';
import '../../../core/crypto/invite_code_service.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/providers/shared_preferences_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/sync/sync_lifecycle_controller.dart';
import '../../../core/theme/design_tokens.dart';
import '../../baby/data/baby_repository.dart';
import '../../baby/data/current_baby_provider.dart';
import '../../../core/families/family_entry.dart';
import '../../../core/families/family_provider.dart';

const _kFamilyIdKey = 'family.id';

const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

/// Plan C-3 §2 — caregiver redeems an invite code, joins the family,
/// pulls the first sync, and lands on Home with K_family installed and
/// baby data already in the local DB.
class ClaimInviteScreen extends ConsumerStatefulWidget {
  const ClaimInviteScreen({super.key});

  @override
  ConsumerState<ClaimInviteScreen> createState() => _ClaimInviteScreenState();
}

class _ClaimInviteScreenState extends ConsumerState<ClaimInviteScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _connecting = false;
  bool _syncing = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    final v = _controller.text.replaceAll('-', '').trim();
    return !_connecting && !_syncing && v.length == 8;
  }

  Future<void> _onConnect() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return;
    final notAdminMsg = context.l10n.claimInviteNotAdmin;
    final notFoundMsg = context.l10n.claimInviteNotFound;
    final expiredMsg = context.l10n.claimInviteExpired;
    final tooManyMsg = context.l10n.claimInviteTooMany;
    final serverErrorMsg = context.l10n.claimInviteServerError;
    setState(() {
      _connecting = true;
      _syncing = false;
      _errorText = null;
    });

    try {
      final supa = Supabase.instance.client;
      if (supa.auth.currentSession == null) {
        // Don't swallow silently — without a session the subsequent
        // claim_invite Edge Function will fail with an opaque "unexpected
        // payload" error. Surface the real cause.
        await supa.auth.signInAnonymously();
      }

      final identity = await DeviceIdentityService(_secureStorage).getOrCreate();
      final resp = await supa.functions.invoke(
        'claim_invite',
        body: {
          'code': raw,
          'device_pub_key': base64Encode(identity.publicKeyBytes),
        },
      );

      if (resp.status == 403) throw Exception(notAdminMsg);
      if (resp.status == 404) throw Exception(notFoundMsg);
      if (resp.status == 410) throw Exception(expiredMsg);
      if (resp.status == 429) throw Exception(tooManyMsg);
      if (resp.status != 200) throw Exception(serverErrorMsg);
      final data = resp.data;
      if (data is! Map) throw Exception('claim_invite returned unexpected payload');

      final salt = base64Decode(
          (data['salt'] as String).replaceAll('\n', '').replaceAll('\r', ''));
      final wrappedKey = base64Decode(
          (data['wrapped_key'] as String).replaceAll('\n', '').replaceAll('\r', ''));
      final familyId = data['family_id'] as String;
      final keyVersion = data['key_version'] as int;

      final familyKeyBytes = await InviteCodeService().unwrapFamilyKey(
        code: raw,
        salt: Uint8List.fromList(salt),
        wrappedKeyEnvelope: Uint8List.fromList(wrappedKey),
        familyId: familyId,
      );

      await FamilyKeyService(_secureStorage).install(
        familyId: familyId,
        bytes: familyKeyBytes,
        keyVersion: keyVersion,
      );

      final prefs = ref.read(sharedPreferencesProvider);
      await prefs.setString(_kFamilyIdKey, familyId);
      await ref.read(familyListProvider.notifier).register(FamilyEntry(
        id: familyId,
        label: 'Joined Family',
        createdAt: DateTime.now().toUtc(),
      ));
      // Mark onboarding done so the router stops redirecting to /welcome.
      await prefs.setBool(kOnboardingDoneKey, true);

      // Rebuild sync controller from no-op → real worker now that family.id exists.
      ref.invalidate(syncLifecycleControllerProvider);

      if (!mounted) return;
      setState(() {
        _connecting = false;
        _syncing = true;
      });

      // Pull all family rows from Supabase and decrypt into local DB.
      await ref.read(syncLifecycleControllerProvider).syncNow();

      // Activate the first baby that arrived via sync.
      final babies = await ref.read(babyRepositoryProvider).list();
      if (babies.isNotEmpty) {
        await ref.read(currentBabyIdProvider.notifier).select(babies.first.id);
      }

      if (!mounted) return;
      context.go(AppRoutes.home);
    } catch (err) {
      if (!mounted) return;
      setState(() => _errorText = err.toString());
    } finally {
      if (mounted) setState(() { _connecting = false; _syncing = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final busy = _connecting || _syncing;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.joinTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.joinHaveCode,
                style: AppTypography.headlineMedium(color: AppColors.inkPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _controller,
                autofocus: true,
                enabled: !busy,
                keyboardType: TextInputType.visiblePassword,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                style: AppTypography.numeric(
                  size: 24,
                  weight: FontWeight.w600,
                  color: AppColors.inkPrimary,
                ),
                textAlign: TextAlign.center,
                inputFormatters: [_InviteCodeFormatter()],
                decoration: InputDecoration(
                  hintText: l10n.joinEnterCode,
                  errorText: _errorText,
                  filled: true,
                  fillColor: AppColors.neutralMuted,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (_) {
                  if (_errorText != null) {
                    setState(() => _errorText = null);
                  } else {
                    setState(() {});
                  }
                },
                onSubmitted: (_) {
                  if (_canSubmit) _onConnect();
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _canSubmit ? _onConnect : null,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(
                  _syncing
                      ? l10n.joinSyncing
                      : _connecting
                          ? l10n.joinConnecting
                          : l10n.joinConnectButton,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Auto-uppercase, strip non-alphanumerics, force the "XXXX-XXXX" shape.
class _InviteCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cleaned = newValue.text
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final capped = cleaned.length > 8 ? cleaned.substring(0, 8) : cleaned;
    final formatted = capped.length > 4
        ? '${capped.substring(0, 4)}-${capped.substring(4)}'
        : capped;
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
