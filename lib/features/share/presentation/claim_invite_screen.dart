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
import '../../../core/theme/design_tokens.dart';

const _kFamilyIdKey = 'family.id';

// flutter_secure_storage v10 migrates legacy entries to custom ciphers
// automatically; no explicit Android options needed.
const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

/// Plan C-3 §2 — caregiver redeems an invite code, joins the family,
/// and lands on Home with K_family installed locally.
class ClaimInviteScreen extends ConsumerStatefulWidget {
  const ClaimInviteScreen({super.key});

  @override
  ConsumerState<ClaimInviteScreen> createState() => _ClaimInviteScreenState();
}

class _ClaimInviteScreenState extends ConsumerState<ClaimInviteScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _connecting = false;
  String? _errorText;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    final v = _controller.text.replaceAll('-', '').trim();
    return !_connecting && v.length == 8;
  }

  Future<void> _onConnect() async {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return;
    setState(() {
      _connecting = true;
      _errorText = null;
    });

    try {
      final supa = Supabase.instance.client;
      // Edge Function requires a JWT — anon counts.
      if (supa.auth.currentSession == null) {
        await supa.auth.signInAnonymously();
      }

      final identity =
          await DeviceIdentityService(_secureStorage).getOrCreate();
      final resp = await supa.functions.invoke(
        'claim_invite',
        body: {
          'code': raw,
          'device_pub_key': base64Encode(identity.publicKeyBytes),
        },
      );

      if (resp.status != 200) {
        throw Exception('claim_invite failed (${resp.status}): ${resp.data}');
      }
      final data = resp.data;
      if (data is! Map) {
        throw Exception('claim_invite returned unexpected payload');
      }
      final salt = base64Decode(data['salt'] as String);
      final wrappedKey = base64Decode(data['wrapped_key'] as String);
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

      if (!mounted) return;
      context.go(AppRoutes.home);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _errorText = err.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.errorGeneric)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _connecting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
                    setState(() {}); // refresh submit-enabled state
                  }
                },
                onSubmitted: (_) {
                  if (_canSubmit) _onConnect();
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _canSubmit ? _onConnect : null,
                icon: _connecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(
                  _connecting ? l10n.joinConnecting : l10n.joinConnectButton,
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
    // Cap to 8 alphanumerics (the code's actual payload).
    final capped =
        cleaned.length > 8 ? cleaned.substring(0, 8) : cleaned;
    final formatted = capped.length > 4
        ? '${capped.substring(0, 4)}-${capped.substring(4)}'
        : capped;
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
