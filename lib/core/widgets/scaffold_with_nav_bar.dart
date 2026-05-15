import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ScaffoldWithNavBar extends StatelessWidget {
  const ScaffoldWithNavBar({super.key, required this.child});
  final Widget child;

  static const _routes = ['/', '/summary', '/stash', '/settings'];
  static const _icons = [
    Icons.home_outlined,
    Icons.bar_chart_outlined,
    Icons.ac_unit_outlined,
    Icons.settings_outlined,
  ];

  int _selectedIndex(String path) {
    if (path == '/') return 0;
    for (var i = 1; i < _routes.length; i++) {
      if (path.startsWith(_routes[i])) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final path = GoRouterState.of(context).uri.path;
    final labels = [l10n.tabHome, l10n.tabSummary, l10n.tabStash, l10n.tabSettings];

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex(path),
        onDestinationSelected: (i) => context.go(_routes[i]),
        destinations: List.generate(
          _routes.length,
          (i) => NavigationDestination(
            icon: Icon(_icons[i]),
            label: labels[i],
          ),
        ),
      ),
    );
  }
}
