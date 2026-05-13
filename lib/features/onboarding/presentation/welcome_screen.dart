import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/providers/shared_preferences_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/design_tokens.dart';

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
    final prefs = ref.read(sharedPreferencesProvider);
    final raw = _nameCtrl.text.trim();
    final name = raw.isEmpty ? 'Baby' : raw;
    await prefs.setString('baby.name', name);
    await prefs.setBool('onboarding.done', true);
    if (!mounted) return;
    context.go(AppRoutes.home);
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
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _start(),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _start,
                child: Text(l10n.welcomeStartCta),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
