import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/diaper/presentation/diaper_log_screen.dart';
import '../../features/feed/presentation/feed_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/pump/presentation/pump_session_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/share/presentation/share_invite_placeholder_screen.dart';
import '../../features/sleep/presentation/sleep_timer_screen.dart';
import '../../features/stash/presentation/stash_list_screen.dart';
import '../providers/shared_preferences_provider.dart';

class AppRoutes {
  AppRoutes._();
  static const welcome      = '/welcome';
  static const home         = '/';
  static const shareInvite  = '/share/invite';
  static const feedNew      = '/feed/new';
  static const pumpNew      = '/pump/new';
  static const settings     = '/settings';
  static const stash        = '/stash';
  static const diaperNew    = '/diaper/new';
  static const sleep        = '/sleep';
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
      GoRoute(
        path: AppRoutes.feedNew,
        builder: (_, __) => const FeedScreen(),
      ),
      GoRoute(
        path: AppRoutes.pumpNew,
        builder: (_, __) => const PumpSessionScreen(),
      ),
      GoRoute(
        path: AppRoutes.settings,
        builder: (_, __) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.stash,
        builder: (_, __) => const StashListScreen(),
      ),
      GoRoute(
        path: AppRoutes.diaperNew,
        builder: (_, __) => const DiaperLogScreen(),
      ),
      GoRoute(
        path: AppRoutes.sleep,
        builder: (_, __) => const SleepTimerScreen(),
      ),
    ],
  );
});
