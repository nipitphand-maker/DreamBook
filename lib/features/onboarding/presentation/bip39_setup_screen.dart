import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/crypto/recovery_code_service.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/providers/shared_preferences_provider.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/design_tokens.dart';

class Bip39SetupScreen extends ConsumerStatefulWidget {
  const Bip39SetupScreen({super.key});

  @override
  ConsumerState<Bip39SetupScreen> createState() => _Bip39SetupScreenState();
}

class _Bip39SetupScreenState extends ConsumerState<Bip39SetupScreen> {
  static const _channel = MethodChannel('dreambook/window_flags');

  final _svc = RecoveryCodeService();
  late final String _code;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _code = _svc.generateCode();
    if (!kIsWeb) {
      _channel.invokeMethod<void>('setSecure', true).catchError((_) {});
    }
  }

  @override
  void dispose() {
    if (!kIsWeb) {
      _channel.invokeMethod<void>('setSecure', false).catchError((_) {});
    }
    super.dispose();
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: _svc.formatCode(_code)));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  void _proceed() {
    context.push(AppRoutes.bip39Verify, extra: _code);
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
    final formatted = _svc.formatCode(_code);

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
                style: AppTypography.bodyMedium(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
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
              // Recovery code display
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xl,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  children: [
                    Text(
                      formatted,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontFamily: 'monospace',
                            letterSpacing: 2,
                            color: scheme.onSurface,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.tonalIcon(
                      onPressed: _copyCode,
                      icon: Icon(
                        _copied ? Icons.check : Icons.copy_outlined,
                        size: 18,
                      ),
                      label: Text(
                        _copied ? l10n.recoverySetupCopied : l10n.recoverySetupCopyCode,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
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
