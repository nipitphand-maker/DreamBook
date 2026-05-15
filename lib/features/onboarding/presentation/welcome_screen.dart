import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/crypto/device_identity_service.dart';
import '../../../core/crypto/family_key_service.dart';
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

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _nameCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final raw = _nameCtrl.text.trim();
      final name = raw.isEmpty ? 'Baby' : raw;
      final prefs = ref.read(sharedPreferencesProvider);

      // Bootstrap MUST run before the baby insert so the baby row gets stamped
      // with the real family_id from prefs. Inserting first leaves family_id
      // as '' (DDL default), which makes BabyRepository.list()'s family.id
      // filter return [] forever.
      final bootstrapped = await _bootstrapFamily(prefs, babyName: name);

      final babyRepo = ref.read(babyRepositoryProvider);
      final today = DateTime.now().toUtc();
      final baby = await babyRepo.insert(name: name, dob: today);
      await ref.read(currentBabyIdProvider.notifier).select(baby.id);

      if (!mounted) return;
      if (bootstrapped) {
        context.go(AppRoutes.bip39Setup);
        return;
      }

      // Offline path: mark onboarding done and go home.
      await prefs.setBool(kOnboardingDoneKey, true);
      final pendingDeepLink = prefs.getString('router.pendingDeepLink');
      if (pendingDeepLink != null && pendingDeepLink.isNotEmpty) {
        await prefs.remove('router.pendingDeepLink');
        if (!mounted) return;
        context.go(pendingDeepLink);
        return;
      }
      if (!mounted) return;
      context.go(AppRoutes.home);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.push(AppRoutes.feedNew);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Returns true if a new family was bootstrapped (online success).
  /// Returns false if already has family, offline, or any error.
  /// Errors are surfaced via SnackBar so the user knows sync won't work —
  /// silent fallback to offline mode masked five production sync failures.
  Future<bool> _bootstrapFamily(
    SharedPreferences prefs, {
    required String babyName,
  }) async {
    if ((prefs.getString(_kFamilyIdKey) ?? '').isNotEmpty) return false;
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
      if (resp.status != 201) {
        debugPrint('bootstrap_family non-201: ${resp.status} ${resp.data}');
        return false;
      }
      final data = resp.data;
      if (data is! Map || data['family_id'] is! String) {
        debugPrint('bootstrap_family bad payload: $data');
        return false;
      }

      final familyId = data['family_id'] as String;
      await prefs.setString(_kFamilyIdKey, familyId);
      await ref.read(familyListProvider.notifier).register(FamilyEntry(
        id: familyId,
        label: "$babyName's Family",
        createdAt: DateTime.now().toUtc(),
      ));
      await FamilyKeyService(_secureStorage).generate(
        familyId: familyId,
        keyVersion: 1,
      );

      ref.invalidate(syncLifecycleControllerProvider);
      ref.read(syncLifecycleControllerProvider).syncNow().ignore();
      return true;
    } catch (e, st) {
      debugPrint('bootstrap_family threw: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync setup failed — continuing offline. ($e)'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xl),
              Text(
                l10n.welcomeHeadline,
                style: AppTypography.headlineLarge(color: scheme.onSurface),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.welcomeSubcopy,
                style: AppTypography.bodyLarge(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              TextField(
                controller: _nameCtrl,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: l10n.welcomeBabyNameLabel,
                  hintText: l10n.welcomeBabyNameHint,
                  counterText: '',
                ),
                autofocus: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _start(),
              ),
              const Spacer(),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else
                FilledButton(
                  onPressed: _start,
                  child: Text(l10n.welcomeStartCta),
                ),
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: () => context.push(AppRoutes.shareClaim),
                child: Text(l10n.joinHaveCode),
              ),
              TextButton(
                onPressed: () => context.push(AppRoutes.bip39Restore),
                child: Text(l10n.welcomeRestoreCta),
              ),
              TextButton(
                onPressed: () => context.push(AppRoutes.cloudRestore),
                child: Text(l10n.welcomeCloudRestoreCta),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
