import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/sync/sync_lifecycle_controller.dart';
import 'core/theme/theme_mode_controller.dart';
import 'l10n/generated/app_localizations.dart';

class DreamBookApp extends ConsumerStatefulWidget {
  const DreamBookApp({super.key});

  @override
  ConsumerState<DreamBookApp> createState() => _DreamBookAppState();
}

class _DreamBookAppState extends ConsumerState<DreamBookApp> {
  @override
  void initState() {
    super.initState();
    // Register the sync lifecycle observer so that returning from
    // background triggers a pull+push cycle. Before caregiver onboarding
    // this resolves to a no-op controller (Plan C-3 wiring).
    WidgetsBinding.instance
        .addObserver(ref.read(syncLifecycleControllerProvider));
  }

  @override
  void dispose() {
    WidgetsBinding.instance
        .removeObserver(ref.read(syncLifecycleControllerProvider));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'DreamBook',
      debugShowCheckedModeBanner: false,
      theme: theme,
      routerConfig: router,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
