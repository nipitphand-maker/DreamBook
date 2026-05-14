import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/crypto/device_identity_service.dart';
import '../../../core/crypto/family_key_service.dart';
import '../../../core/crypto/invite_code_service.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/providers/shared_preferences_provider.dart';
import '../../../core/theme/design_tokens.dart';

const _kFamilyIdKey = 'family.id';
const Duration _kInviteTtl = Duration(hours: 1);

// Plan C spec mandates encrypted shared preferences on Android; the
// flutter_secure_storage v10 plugin migrates legacy entries to custom
// ciphers automatically, so no explicit option is required.
const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

/// Plan C-3 §1 — caregiver invite generation screen.
///
/// On first load:
///   1. If `family.id` is absent → call `bootstrap_family` Edge Function,
///      persist `family.id` + generate `K_family` locally.
///   2. Generate an 8-char Crockford code, wrap K_family under
///      Argon2id(code)+salt, store the wrap on the server via
///      `create_invite`. Show code + QR + 60-min countdown.
///
/// Code is regenerable; each tap of "New code" creates a fresh invite
/// row with the same family_id.
class ShareInviteScreen extends ConsumerStatefulWidget {
  const ShareInviteScreen({super.key});

  @override
  ConsumerState<ShareInviteScreen> createState() => _ShareInviteScreenState();
}

class _ShareInviteScreenState extends ConsumerState<ShareInviteScreen> {
  // Placeholder until Plan D introduces real baby name into the share flow.
  static const String _babyNamePlaceholder = 'Baby';

  _ScreenStatus _status = _ScreenStatus.bootstrapping;
  String? _errorMessage;
  String? _code;
  DateTime? _expiresAt;
  Timer? _ticker;
  int _minutesRemaining = _kInviteTtl.inMinutes;

  late final InviteCodeService _inviteSvc;
  late final FamilyKeyService _familyKeys;
  late final DeviceIdentityService _identity;

  @override
  void initState() {
    super.initState();
    _inviteSvc = InviteCodeService();
    _familyKeys = FamilyKeyService(_secureStorage);
    _identity = DeviceIdentityService(_secureStorage);
    // Kick off async work after first frame so we can read providers safely.
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrapAndGenerate());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _bootstrapAndGenerate() async {
    setState(() {
      _status = _ScreenStatus.bootstrapping;
      _errorMessage = null;
    });
    try {
      final familyId = await _ensureFamily();
      await _generateInvite(familyId: familyId);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _status = _ScreenStatus.error;
        _errorMessage = err.toString();
      });
    }
  }

  /// Returns existing family id from prefs, or bootstraps a new family and
  /// generates a fresh K_family locally.
  Future<String> _ensureFamily() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final existing = prefs.getString(_kFamilyIdKey);
    if (existing != null && existing.isNotEmpty) {
      // Self-heal: if we have a family id but no key locally, regenerate.
      final stored = await _familyKeys.read(familyId: existing);
      if (stored == null) {
        await _familyKeys.generate(familyId: existing, keyVersion: 1);
      }
      return existing;
    }

    // Ensure anonymous session is live before invoking Edge Function.
    final supa = Supabase.instance.client;
    if (supa.auth.currentSession == null) {
      await supa.auth.signInAnonymously();
    }

    final identity = await _identity.getOrCreate();
    final resp = await supa.functions.invoke(
      'bootstrap_family',
      body: {'device_pub_key': base64Encode(identity.publicKeyBytes)},
    );
    if (resp.status != 200 && resp.status != 201) {
      throw Exception(
        'bootstrap_family failed (${resp.status}): ${resp.data}',
      );
    }
    final data = resp.data;
    if (data is! Map || data['family_id'] is! String) {
      throw Exception('bootstrap_family returned unexpected payload');
    }
    final familyId = data['family_id'] as String;
    await prefs.setString(_kFamilyIdKey, familyId);
    // First key for a fresh family is always version 1.
    await _familyKeys.generate(familyId: familyId, keyVersion: 1);
    return familyId;
  }

  /// Creates a fresh invite code + posts the wrapped K_family to the server.
  Future<void> _generateInvite({required String familyId}) async {
    setState(() {
      _status = _ScreenStatus.generating;
      _errorMessage = null;
    });

    final code = _inviteSvc.generateCode();
    final codeHashBytes = await _inviteSvc.hashCode_(code);
    final codeHashHex = codeHashBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    final familyKey = await _familyKeys.read(familyId: familyId);
    if (familyKey == null) {
      throw StateError('Family key missing — re-bootstrap required');
    }
    final wrapped = await _inviteSvc.wrapFamilyKey(
      code: code,
      familyKey: familyKey.bytes,
      familyId: familyId,
    );
    final expiresAt = DateTime.now().toUtc().add(_kInviteTtl);

    final supa = Supabase.instance.client;
    final resp = await supa.functions.invoke(
      'create_invite',
      body: {
        'family_id': familyId,
        'code_hash': codeHashHex,
        'salt': base64Encode(wrapped.salt),
        'wrapped_key': base64Encode(wrapped.wrappedKeyEnvelope),
        'expires_at': expiresAt.toIso8601String(),
      },
    );
    if (resp.status != 200 && resp.status != 201) {
      throw Exception(
        'create_invite failed (${resp.status}): ${resp.data}',
      );
    }

    if (!mounted) return;
    setState(() {
      _code = code;
      _expiresAt = expiresAt;
      _status = _ScreenStatus.ready;
      _minutesRemaining = _kInviteTtl.inMinutes;
    });
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      final expiresAt = _expiresAt;
      if (expiresAt == null) return;
      final remaining = expiresAt.difference(DateTime.now().toUtc());
      if (!mounted) return;
      setState(() {
        _minutesRemaining = remaining.inMinutes.clamp(0, _kInviteTtl.inMinutes);
      });
      if (remaining <= Duration.zero) {
        _ticker?.cancel();
      }
    });
  }

  Future<void> _onRegenerate() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final familyId = prefs.getString(_kFamilyIdKey);
    if (familyId == null) {
      await _bootstrapAndGenerate();
      return;
    }
    try {
      await _generateInvite(familyId: familyId);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _status = _ScreenStatus.error;
        _errorMessage = err.toString();
      });
    }
  }

  Future<void> _onShare() async {
    final code = _code;
    if (code == null) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.actionDone)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.shareTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: switch (_status) {
            _ScreenStatus.bootstrapping || _ScreenStatus.generating =>
              _LoadingView(
                message: _status == _ScreenStatus.bootstrapping
                    ? l10n.shareBootstrapping
                    : l10n.loading,
              ),
            _ScreenStatus.error => _ErrorView(
                message: _errorMessage ?? l10n.errorGeneric,
                onRetry: _bootstrapAndGenerate,
              ),
            _ScreenStatus.ready => _ReadyView(
                code: _code!,
                babyName: _babyNamePlaceholder,
                minutesRemaining: _minutesRemaining,
                onShare: _onShare,
                onRegenerate: _onRegenerate,
              ),
          },
        ),
      ),
    );
  }
}

enum _ScreenStatus { bootstrapping, generating, ready, error }

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium(color: AppColors.inkSecondary),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.error_outline,
              size: 48, color: AppColors.inkSecondary),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium(color: AppColors.inkSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: onRetry,
            child: Text(l10n.actionRetry),
          ),
        ],
      ),
    );
  }
}

class _ReadyView extends StatelessWidget {
  const _ReadyView({
    required this.code,
    required this.babyName,
    required this.minutesRemaining,
    required this.onShare,
    required this.onRegenerate,
  });

  final String code;
  final String babyName;
  final int minutesRemaining;
  final VoidCallback onShare;
  final Future<void> Function() onRegenerate;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sm),
        Text(
          l10n.shareInviteHeadline(babyName),
          textAlign: TextAlign.center,
          style: AppTypography.headlineMedium(color: AppColors.inkPrimary),
        ),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: QrImageView(
              data: code,
              size: 200,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          l10n.shareInviteCodeLabel,
          textAlign: TextAlign.center,
          style: AppTypography.labelLarge(color: AppColors.inkSecondary),
        ),
        const SizedBox(height: AppSpacing.xs),
        SelectableText(
          code,
          textAlign: TextAlign.center,
          style: AppTypography.statHero(color: AppColors.lavender700),
        ),
        const SizedBox(height: AppSpacing.xs),
        Center(
          child: Chip(
            label: Text(l10n.shareInviteExpiresIn(minutesRemaining)),
            backgroundColor: AppColors.neutralMuted,
            side: BorderSide.none,
          ),
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: onShare,
          icon: const Icon(Icons.share_outlined),
          label: Text(l10n.shareInviteShareVia),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextButton.icon(
          onPressed: onRegenerate,
          icon: const Icon(Icons.refresh),
          label: Text(l10n.shareInviteRegenerate),
        ),
      ],
    );
  }
}
