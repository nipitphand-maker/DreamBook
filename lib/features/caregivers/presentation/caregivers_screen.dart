import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/design_tokens.dart';

class CaregiversScreen extends StatelessWidget {
  const CaregiversScreen({super.key});

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
              const Icon(Icons.group_outlined,
                  size: 56, color: AppColors.lavender700),
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.shareJustYou,
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium(color: AppColors.inkSecondary),
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton.icon(
                onPressed: () => context.push(AppRoutes.shareInvite),
                icon: const Icon(Icons.person_add_outlined),
                label: Text(l10n.shareInviteCta),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () => context.push(AppRoutes.shareClaim),
                icon: const Icon(Icons.input_outlined),
                label: Text(l10n.joinHaveCode),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
