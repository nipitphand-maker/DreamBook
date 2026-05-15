import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/crypto/bip39_service.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/providers/shared_preferences_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/design_tokens.dart';

const _secureChannel = MethodChannel('dreambook/window_flags');

class Bip39SetupScreen extends ConsumerStatefulWidget {
  const Bip39SetupScreen({super.key});

  @override
  ConsumerState<Bip39SetupScreen> createState() => _Bip39SetupScreenState();
}

class _Bip39SetupScreenState extends ConsumerState<Bip39SetupScreen> {
  final _bip39 = Bip39Service();
  late String _phrase;

  @override
  void initState() {
    super.initState();
    _phrase = _bip39.generatePhrase();
    _setSecureFlag(true);
  }

  @override
  void dispose() {
    _setSecureFlag(false);
    super.dispose();
  }

  void _setSecureFlag(bool secure) {
    _secureChannel.invokeMethod<void>('setSecure', secure).catchError((_) {});
  }

  void _proceed() {
    context.push(AppRoutes.bip39Verify, extra: _phrase);
  }

  void _remindLater() {
    final prefs = ref.read(sharedPreferencesProvider);
    prefs.setBool(kOnboardingDoneKey, true);
    context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final words = _bip39.toWords(_phrase);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(l10n.recoverySetupHeadline),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.recoverySetupSubcopy,
                style: AppTypography.bodyMedium(color: scheme.onSurface.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  l10n.recoverySetupWarning,
                  style: AppTypography.bodyMedium(color: scheme.error),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 2.8,
                    crossAxisSpacing: AppSpacing.xs,
                    mainAxisSpacing: AppSpacing.xs,
                  ),
                  itemCount: 12,
                  itemBuilder: (context, i) {
                    return Container(
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${i + 1}. ${words[i]}',
                        style: AppTypography.bodyMedium(color: scheme.onSurface),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: _proceed,
                child: Text(l10n.recoverySetupWrittenCta),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: _remindLater,
                child: Text(l10n.recoverySetupRemindLater),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}
