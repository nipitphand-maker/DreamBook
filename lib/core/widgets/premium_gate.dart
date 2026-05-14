import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/premium_provider.dart';
import '../router/app_router.dart';

/// Wraps [child] and shows [lockedChild] (or a default paywall prompt) when
/// the user is not premium. Tapping the locked state navigates to the paywall.
class PremiumGate extends ConsumerWidget {
  const PremiumGate({
    super.key,
    required this.child,
    this.lockedChild,
  });

  final Widget child;

  /// Optional alternative widget to show when feature is locked.
  /// If null, a default "Upgrade" chip is shown.
  final Widget? lockedChild;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final premiumAsync = ref.watch(isPremiumProvider);
    return premiumAsync.when(
      data: (isPremium) => isPremium
          ? child
          : GestureDetector(
              onTap: () => context.push(AppRoutes.premium),
              child: lockedChild ?? const _DefaultLockedWidget(),
            ),
      loading: () => child,
      error: (_, __) => child,
    );
  }
}

class _DefaultLockedWidget extends StatelessWidget {
  const _DefaultLockedWidget();

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.lock_outline, size: 14),
      label: const Text('Premium'),
      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
    );
  }
}
