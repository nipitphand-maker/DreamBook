import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/crypto/device_identity_service.dart';
import '../../../core/crypto/family_key_service.dart';
import '../../../core/crypto/key_rotation_service.dart';
import '../../../core/db/database_provider.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/providers/shared_preferences_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/sync/bytea_codec.dart';
import '../../../core/sync/sync_constants.dart';
import '../../../core/theme/design_tokens.dart';

const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

class _DeviceRow {
  _DeviceRow({
    required this.deviceFpDisplay,
    required this.deviceFpFull,
    required this.role,
    required this.joinedAt,
    required this.isThisDevice,
    required this.nickname,
  });
  final String deviceFpDisplay;
  final String deviceFpFull;
  final String role;
  final DateTime joinedAt;
  final bool isThisDevice;
  String nickname;
}

class ManageDevicesScreen extends ConsumerStatefulWidget {
  const ManageDevicesScreen({super.key});

  @override
  ConsumerState<ManageDevicesScreen> createState() => _ManageDevicesScreenState();
}

class _ManageDevicesScreenState extends ConsumerState<ManageDevicesScreen> {
  List<_DeviceRow>? _devices;
  String? _errorText;
  bool _loading = true;
  String? _myFpHex;

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  static String _nicknameKey(String deviceFp) => 'device.nickname.$deviceFp';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final identity = await DeviceIdentityService(_secureStorage).getOrCreate();
      // Compute device_fp = SHA-256(pubkey)[0:16], same as EF logic.
      final hashBuf = await Sha256().hash(identity.publicKeyBytes);
      _myFpHex = hashBuf.bytes.sublist(0, 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

      final supa = Supabase.instance.client;
      final rows = await supa
          .from('family_devices')
          .select('device_fp, role, joined_at')
          .filter('revoked_at', 'is', null)
          .order('joined_at', ascending: true);

      final prefs = _prefs;
      final devices = (rows as List).map((r) {
        final m = r as Map<String, dynamic>;
        final fpBytes = decodeBytea(m['device_fp']);
        final fpHex = fpBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
        final fpDisplay = fpHex.length > 8 ? '${fpHex.substring(0, 8)}…' : fpHex;
        final nickname = prefs.getString(_nicknameKey(fpHex)) ?? '';
        return _DeviceRow(
          deviceFpDisplay: fpDisplay,
          deviceFpFull: fpHex,
          role: m['role'] as String? ?? 'editor',
          joinedAt: DateTime.parse(m['joined_at'] as String),
          isThisDevice: fpHex == _myFpHex,
          nickname: nickname,
        );
      }).toList();

      if (mounted) setState(() { _devices = devices; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _errorText = e.toString(); _loading = false; });
    }
  }

  Future<void> _renameDevice(_DeviceRow device) async {
    final l10n = context.l10n;
    final controller = TextEditingController(text: device.nickname);
    final saved = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deviceNicknameEdit),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: l10n.deviceNicknameHint),
          textCapitalization: TextCapitalization.words,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.manageDevicesRevokeCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(l10n.deviceNicknameSave),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == null || !mounted) return;
    final key = _nicknameKey(device.deviceFpFull);
    if (saved.isEmpty) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, saved);
    }
    setState(() {
      device.nickname = saved;
    });
  }

  Future<void> _revoke(_DeviceRow device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.manageDevicesRevokeConfirmTitle),
        content: Text(ctx.l10n.manageDevicesRevokeConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.manageDevicesRevokeCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.manageDevicesRevokeConfirmCta),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final familyId = _prefs.getString(kFamilyIdPrefsKey);
      if (familyId == null) throw StateError('family.id not in prefs');

      final db = await ref.read(appDatabaseProvider.future);
      final krs = KeyRotationService(
        db: db,
        familyKeys: FamilyKeyService(_secureStorage),
      );

      // Record rotation intent BEFORE server call (crash-safe).
      await krs.beginRotation(familyId: familyId);

      final supa = Supabase.instance.client;
      await supa.functions.invoke(
        'revoke_caregiver',
        body: {'target_device_fp': device.deviceFpFull},
      );

      // Rotate local K_family so the revoked device can't decrypt future data.
      await krs.completeRotation(familyId: familyId);

      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.manageDevicesHeadline)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorText != null
              ? Center(child: Text(_errorText!, style: TextStyle(color: scheme.error)))
              : _devices!.isEmpty
                  ? Center(child: Text(l10n.manageDevicesEmpty))
                  : ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      itemCount: _devices!.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final d = _devices![i];
                        // Nickname always wins; "This device" is just the
                        // default label when no nickname is set on own row.
                        final displayName = d.nickname.isNotEmpty
                            ? d.nickname
                            : d.isThisDevice
                                ? l10n.manageDevicesThisDevice
                                : d.deviceFpDisplay;
                        final roleLabel = d.role == 'admin'
                            ? l10n.manageDevicesAdmin
                            : l10n.manageDevicesEditor;
                        final joinedDate =
                            d.joinedAt.toLocal().toString().substring(0, 10);
                        // Suffix "· This device" on the subtitle so the user
                        // can still identify their own row after renaming.
                        final subtitle = d.isThisDevice
                            ? (d.nickname.isNotEmpty
                                ? '$roleLabel · $joinedDate · ${l10n.manageDevicesThisDevice}'
                                : '$roleLabel · $joinedDate')
                            : '$roleLabel · $joinedDate';
                        return ListTile(
                          leading: Icon(
                            d.role == 'admin'
                                ? Icons.admin_panel_settings
                                : Icons.person,
                          ),
                          title: Text(displayName),
                          subtitle: Text(subtitle),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: l10n.deviceNicknameEdit,
                                onPressed: () => _renameDevice(d),
                              ),
                              if (!d.isThisDevice)
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  tooltip: l10n.manageDevicesRevokeButton,
                                  onPressed: () => _revoke(d),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.shareInvite),
        icon: const Icon(Icons.add),
        label: Text(l10n.manageDevicesRecoveryInvite),
      ),
    );
  }
}
