import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/baby/presentation/baby_switcher_screen.dart';
import '../../features/onboarding/presentation/feature_tour_screen.dart';
import '../../features/diaper/presentation/diaper_log_screen.dart';
import '../../features/feed/presentation/feed_screen.dart';
import '../../features/medication/presentation/medication_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/onboarding/presentation/welcome_screen.dart';
import '../../features/temperature/presentation/temperature_screen.dart';
import '../../features/onboarding/presentation/bip39_setup_screen.dart';
import '../../features/onboarding/presentation/bip39_verify_screen.dart';
import '../../features/onboarding/presentation/bip39_restore_screen.dart';
import '../../features/pump/presentation/pump_session_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/manage_devices_screen.dart';
import '../../features/settings/presentation/cloud_backup_screen.dart';
import '../../features/onboarding/presentation/cloud_restore_screen.dart';
import '../../features/share/presentation/claim_invite_screen.dart';
import '../../features/share/presentation/share_invite_screen.dart';
import '../../features/sleep/presentation/sleep_timer_screen.dart';
import '../../features/stash/presentation/stash_list_screen.dart';
import '../../features/subscription/presentation/paywall_screen.dart';
import '../../features/summary/presentation/daily_summary_screen.dart';
import '../../features/milestone/presentation/milestone_screen.dart';
import '../../features/vaccination/presentation/vaccination_log_screen.dart';
import '../../features/visit_report/presentation/visit_report_screen.dart';
import '../providers/shared_preferences_provider.dart';
import '../widgets/scaffold_with_nav_bar.dart';

class AppRoutes {
  AppRoutes._();
  static const welcome      = '/welcome';
  static const home         = '/';
  static const caregivers   = '/caregivers';
  static const shareInvite  = '/share/invite';
  static const shareClaim   = '/share/claim';
  static const babies       = '/babies';
  static const premium      = '/settings/premium';
  static const feedNew      = '/feed/new';
  static const pumpNew      = '/pump/new';
  static const settings     = '/settings';
  static const stash        = '/stash';
  static const diaperNew    = '/diaper/new';
  static const sleep        = '/sleep';
  static const summary      = '/summary';
  static const vaccination  = '/vaccination';
  static const visitReport  = '/visit-report';
  static const bip39Setup   = '/recovery/setup';
  static const bip39Verify  = '/recovery/verify';
  static const bip39Restore = '/recovery/restore';
  static const manageDevices = '/settings/devices';
  static const cloudBackup   = '/settings/cloud-backup';
  static const families      = '/settings/families';
  static const cloudRestore   = '/recovery/cloud-restore';
  static const milestones     = '/milestones';
  static const temperatureNew = '/temperature/new';
  static const medicationNew  = '/medication/new';
  static const featureTour    = '/feature-tour';
}

const kOnboardingDoneKey = 'onboarding.done';
const kFeatureTourSeenKey = 'feature.tour.seen';

final appRouterProvider = Provider<GoRouter>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return GoRouter(
    initialLocation: AppRoutes.home,
    redirect: (context, state) {
      final onboarded = prefs.getBool(kOnboardingDoneKey) ?? false;
      if (!onboarded &&
          state.matchedLocation != AppRoutes.welcome &&
          state.matchedLocation != AppRoutes.shareClaim &&
          state.matchedLocation != AppRoutes.shareInvite &&
          state.matchedLocation != AppRoutes.bip39Setup &&
          state.matchedLocation != AppRoutes.bip39Verify &&
          state.matchedLocation != AppRoutes.bip39Restore &&
          state.matchedLocation != AppRoutes.cloudRestore &&
          state.matchedLocation != AppRoutes.featureTour) {
        // B-2: Save the intended deep-link path so WelcomeScreen can
        // resume it after onboarding completes.
        final intended = state.uri.toString();
        if (intended != AppRoutes.home) {
          prefs.setString('router.pendingDeepLink', intended);
        }
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
      // Shell wraps the 4 primary tab destinations with the bottom nav bar.
      ShellRoute(
        builder: (context, state, child) => ScaffoldWithNavBar(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (_, __) => const HomeScreen(),
          ),
          GoRoute(
            path: AppRoutes.summary,
            builder: (_, __) => const DailySummaryScreen(),
          ),
          GoRoute(
            path: AppRoutes.stash,
            builder: (_, __) => const StashListScreen(),
          ),
          GoRoute(
            path: AppRoutes.settings,
            builder: (_, __) => const SettingsScreen(),
          ),
        ],
      ),
      // Full-screen routes — no bottom nav shown.
      //
      // Caregivers route folded into the merged Manage Devices screen.
      // The constant is kept so existing call sites in home_screen.dart
      // (and any deep links) keep working — the redirect lands them on
      // the single canonical surface.
      GoRoute(
        path: AppRoutes.caregivers,
        redirect: (_, __) => AppRoutes.manageDevices,
      ),
      GoRoute(
        path: AppRoutes.shareInvite,
        builder: (_, __) => const ShareInviteScreen(),
      ),
      GoRoute(
        path: AppRoutes.shareClaim,
        builder: (_, __) => const ClaimInviteScreen(),
      ),
      GoRoute(
        path: AppRoutes.babies,
        builder: (_, __) => const BabySwitcherScreen(),
      ),
      GoRoute(
        path: AppRoutes.premium,
        builder: (_, __) => const PaywallScreen(),
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
        path: AppRoutes.diaperNew,
        builder: (_, __) => const DiaperLogScreen(),
      ),
      GoRoute(
        path: AppRoutes.sleep,
        builder: (_, __) => const SleepTimerScreen(),
      ),
      GoRoute(
        path: AppRoutes.vaccination,
        builder: (_, __) => const VaccinationLogScreen(),
      ),
      GoRoute(
        // TODO: add entry point in SettingsScreen
        path: AppRoutes.visitReport,
        builder: (_, __) => const VisitReportScreen(),
      ),
      GoRoute(
        path: AppRoutes.bip39Setup,
        builder: (_, __) => const Bip39SetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.bip39Verify,
        redirect: (context, state) =>
            state.extra is String ? null : AppRoutes.bip39Setup,
        builder: (context, state) =>
            Bip39VerifyScreen(phrase: state.extra as String),
      ),
      GoRoute(
        path: AppRoutes.bip39Restore,
        builder: (_, __) => const Bip39RestoreScreen(),
      ),
      GoRoute(
        path: AppRoutes.manageDevices,
        builder: (_, __) => const ManageDevicesScreen(),
      ),
      GoRoute(
        path: AppRoutes.cloudBackup,
        builder: (_, __) => const CloudBackupScreen(),
      ),
      // Families route folded into Manage Devices for MVP. The settings tile
      // and the home banner both link to AppRoutes.families — keep the
      // constant + route, but redirect so users land on the single surface.
      GoRoute(
        path: AppRoutes.families,
        redirect: (_, __) => AppRoutes.manageDevices,
      ),
      GoRoute(
        path: AppRoutes.cloudRestore,
        builder: (_, __) => const CloudRestoreScreen(),
      ),
      GoRoute(
        path: AppRoutes.milestones,
        builder: (_, __) => const MilestoneScreen(),
      ),
      GoRoute(
        path: AppRoutes.temperatureNew,
        builder: (_, __) => const TemperatureScreen(),
      ),
      GoRoute(
        path: AppRoutes.medicationNew,
        builder: (_, __) => const MedicationScreen(),
      ),
      GoRoute(
        path: AppRoutes.featureTour,
        builder: (_, __) => const FeatureTourScreen(),
      ),
    ],
  );
});
