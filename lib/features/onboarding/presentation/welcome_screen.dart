import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/providers/shared_preferences_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/design_tokens.dart';
import '../../baby/data/baby_repository.dart';
import '../../baby/data/current_baby_provider.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _nameCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    // Activation-first: baby name is optional. Default 'Baby' if empty.
    // Routes to /home in Plan A; Plan B will retarget to /feed/new so the
    // primary CTA "Log a feed now" delivers immediate value.
    final raw = _nameCtrl.text.trim();
    final name = raw.isEmpty ? 'Baby' : raw;

    // Plan B: create the Baby row + flip the current-baby pointer.
    final babyRepo = ref.read(babyRepositoryProvider);
    final today = DateTime.now().toUtc();
    final baby = await babyRepo.insert(name: name, dob: today);
    await ref.read(currentBabyIdProvider.notifier).select(baby.id);

    // Mark onboarding done. R-4: use shared constant kOnboardingDoneKey.
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(kOnboardingDoneKey, true);

    if (!mounted) return;

    // B-2: If a deep link was saved before onboarding, navigate there.
    final pendingDeepLink = prefs.getString('router.pendingDeepLink');
    if (pendingDeepLink != null && pendingDeepLink.isNotEmpty) {
      await prefs.remove('router.pendingDeepLink');
      if (!mounted) return;
      context.go(pendingDeepLink);
      return;
    }

    // B-1: Set home as back-stack root, then push feed/new on top so that
    // pressing back from feed/new returns to home rather than welcome.
    context.go(AppRoutes.home);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.push(AppRoutes.feedNew);
    });
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
                decoration: InputDecoration(
                  labelText: l10n.welcomeBabyNameLabel,
                  hintText: l10n.welcomeBabyNameHint,
                ),
                autofocus: false,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _start(),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _start,
                child: Text(l10n.welcomeStartCta),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: () => context.push(AppRoutes.shareClaim),
                child: Text(l10n.joinHaveCode),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
