import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/home_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/share/presentation/share_invite_placeholder_screen.dart';
import '../providers/shared_preferences_provider.dart';

class AppRoutes {
  AppRoutes._();
  static const welcome      = '/welcome';
  static const home         = '/';
  static const shareInvite  = '/share/invite';
}

const _kOnboardingDoneKey = 'onboarding.done';

final appRouterProvider = Provider<GoRouter>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return GoRouter(
    initialLocation: AppRoutes.home,
    redirect: (context, state) {
      final onboarded = prefs.getBool(_kOnboardingDoneKey) ?? false;
      if (!onboarded && state.matchedLocation != AppRoutes.welcome) {
        return AppRoutes.welcome;
      }
      if (onboarded && state.matchedLocation == AppRoutes.welcome) {
        return AppRoutes.home;
      }
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.welcome,
        builder: (_, __) => const WelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.shareInvite,
        builder: (_, __) => const ShareInvitePlaceholderScreen(),
      ),
    ],
  );
});
