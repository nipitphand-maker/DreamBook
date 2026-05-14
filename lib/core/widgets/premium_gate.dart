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

    Widget locked() => GestureDetector(
          onTap: () => context.push(AppRoutes.premium),
          child: lockedChild ?? const _DefaultLockedWidget(),
        );

    return premiumAsync.when(
      data: (isPremium) => isPremium ? child : locked(),
      // While RC entitlement is loading we briefly show the unlocked child to
      // avoid a flicker on cold start — the loading window is typically <1s.
      loading: () => child,
      // On error (network, RC outage), fail CLOSED — show locked, not
      // unlocked. Otherwise an offline / RC outage would grant Premium to
      // everyone. The gate is one tap from the paywall so this is safe.
      error: (_, __) => locked(),
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
