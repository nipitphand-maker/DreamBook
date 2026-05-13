import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/theme/design_tokens.dart';

class ShareInvitePlaceholderScreen extends StatelessWidget {
  const ShareInvitePlaceholderScreen({super.key});

  // Hardcoded sample. Plan C: replaced by InviteCodeService.generate().
  // Format: XXXX-XXXX Crockford base32 (no I/L/O/U); one hyphen at pos 4.
  static const String _sampleCode = 'MK29-HFX4';
  static const String _sampleBabyName = 'Mali';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.shareTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.shareInviteHeadline(_sampleBabyName),
                textAlign: TextAlign.center,
                style: AppTypography.headlineMedium(color: AppColors.inkPrimary),
              ),
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    color: AppColors.neutralMuted,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                  ),
                  child: const Center(
                    child: Icon(Icons.qr_code_2_outlined, size: 96),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Or read this aloud',
                textAlign: TextAlign.center,
                style: AppTypography.labelLarge(color: AppColors.inkSecondary),
              ),
              const SizedBox(height: AppSpacing.xs),
              SelectableText(
                _sampleCode,
                textAlign: TextAlign.center,
                style: AppTypography.statHero(color: AppColors.lavender700),
              ),
              const SizedBox(height: AppSpacing.xs),
              Center(
                child: Chip(
                  label: Text(l10n.shareInviteExpiresIn(60)),
                  backgroundColor: AppColors.neutralMuted,
                  side: BorderSide.none,
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    const ClipboardData(text: _sampleCode),
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.actionDone)),
                  );
                },
                icon: const Icon(Icons.share_outlined),
                label: Text(l10n.shareInviteShareVia),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
