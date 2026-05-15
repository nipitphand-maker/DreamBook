import 'dart:async';
import 'dart:convert';

import 'package:dreambook/core/crypto/device_identity_service.dart';
import 'package:dreambook/core/crypto/family_key_service.dart';
import 'package:dreambook/core/families/family_entry.dart';
import 'package:dreambook/core/families/family_provider.dart';
import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/providers/premium_provider.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/core/router/app_router.dart';
import 'package:dreambook/core/sync/sync_lifecycle_controller.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _secureStorage = FlutterSecureStorage();

class FamiliesScreen extends ConsumerStatefulWidget {
  const FamiliesScreen({super.key});

  @override
  ConsumerState<FamiliesScreen> createState() => _FamiliesScreenState();
}

class _FamiliesScreenState extends ConsumerState<FamiliesScreen> {
  bool _adding = false;

  Future<void> _switchTo(String familyId) async {
    await ref.read(familyListProvider.notifier).switchTo(familyId);
    await ref.read(currentBabyIdProvider.notifier).clear();
    ref.invalidate(syncLifecycleControllerProvider);
    ref.read(syncLifecycleControllerProvider).syncNow().ignore();
    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  Future<void> _leave(FamilyEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.familiesLeaveConfirmTitle),
        content: Text(ctx.l10n.familiesLeaveConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.familiesLeaveCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.familiesLeaveConfirmCta),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await FamilyKeyService(_secureStorage).clear(familyId: entry.id);
    await ref.read(familyListProvider.notifier).remove(entry.id);
    ref.invalidate(syncLifecycleControllerProvider);
  }

  Future<void> _addFamily() async {
    final families = ref.read(familyListProvider);
    final isPremium = await ref.read(isPremiumProvider.future);

    if (!ref.read(familyRepositoryProvider).canAddFamily(
          isPremium: isPremium,
          currentCount: families.length,
        )) {
      if (!mounted) return;
      unawaited(context.push(AppRoutes.premium));
      return;
    }

    setState(() => _adding = true);
    try {
      final supa = Supabase.instance.client;
      if (supa.auth.currentSession == null) {
        await supa.auth.signInAnonymously();
      }

      final identity = await DeviceIdentityService(_secureStorage).getOrCreate();
      final resp = await supa.functions.invoke(
        'bootstrap_family',
        body: {'device_pub_key': base64Encode(identity.publicKeyBytes)},
      );
      if (resp.status != 201) throw Exception('bootstrap_family: ${resp.status}');

      final data = resp.data;
      if (data is! Map || data['family_id'] is! String) {
        throw Exception('bootstrap_family returned unexpected payload');
      }
      final familyId = data['family_id'] as String;

      await FamilyKeyService(_secureStorage).generate(
        familyId: familyId,
        keyVersion: 1,
      );

      final n = families.length + 1;
      await ref.read(familyListProvider.notifier).register(FamilyEntry(
            id: familyId,
            label: 'Family $n',
            createdAt: DateTime.now().toUtc(),
          ));

      await ref.read(sharedPreferencesProvider).setString('family.id', familyId);
      await ref.read(familyListProvider.notifier).switchTo(familyId);
      await ref.read(currentBabyIdProvider.notifier).clear();
      ref.invalidate(syncLifecycleControllerProvider);
      ref.read(syncLifecycleControllerProvider).syncNow().ignore();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.familiesCreated)),
      );
      context.go(AppRoutes.home);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.familiesCreatedError)),
      );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final families = ref.watch(familyListProvider);
    final activeId = ref.read(familyRepositoryProvider).activeId();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.familiesTitle)),
      body: families.isEmpty
          ? Center(child: Text(l10n.familiesEmpty))
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              itemCount: families.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final entry = families[i];
                final isActive = entry.id == activeId;
                return ListTile(
                  leading: Icon(
                    Icons.group_outlined,
                    color: isActive
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(entry.label),
                  subtitle: isActive ? Text(l10n.familiesActive) : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isActive)
                        TextButton(
                          onPressed: () => _switchTo(entry.id),
                          child: Text(l10n.familiesSwitch),
                        ),
                      if (families.length > 1)
                        TextButton(
                          onPressed: () => _leave(entry),
                          style: TextButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.error,
                          ),
                          child: Text(l10n.familiesLeave),
                        ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: _adding
          ? const FloatingActionButton(
              onPressed: null,
              child: CircularProgressIndicator(),
            )
          : FloatingActionButton.extended(
              onPressed: _addFamily,
              icon: const Icon(Icons.add),
              label: Text(l10n.familiesAddAnother),
            ),
    );
  }
}
