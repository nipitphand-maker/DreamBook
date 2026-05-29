import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/router/app_router.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class FeatureTourScreen extends StatefulWidget {
  const FeatureTourScreen({super.key});

  @override
  State<FeatureTourScreen> createState() => _FeatureTourScreenState();
}

class _FeatureTourScreenState extends State<FeatureTourScreen> {
  final _controller = PageController();
  int _currentPage = 0;
  static const int _pageCount = 4;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goHome() => context.go(AppRoutes.home);

  void _nextPage() {
    _controller.nextPage(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final isLastPage = _currentPage == _pageCount - 1;

    final pages = [
      _TourPage(
        icon: Icons.edit_note_outlined,
        title: l10n.tourPage1Title,
        body: l10n.tourPage1Body,
      ),
      _TourPage(
        icon: Icons.group_outlined,
        title: l10n.tourPage2Title,
        body: l10n.tourPage2Body,
      ),
      _TourPage(
        icon: Icons.lock_outline,
        title: l10n.tourPage3Title,
        body: l10n.tourPage3Body,
      ),
      _TourPage(
        icon: Icons.favorite_border_outlined,
        title: l10n.tourPage4Title,
        body: l10n.tourPage4Body,
      ),
    ];

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Stack(
          children: [
            // Skip button top-right
            Positioned(
              top: AppSpacing.xs,
              right: AppSpacing.sm,
              child: TextButton(
                onPressed: _goHome,
                child: Text(
                  l10n.tourSkip,
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ),

            // Main content
            Column(
              children: [
                // Page view
                Expanded(
                  child: PageView(
                    controller: _controller,
                    onPageChanged: (i) => setState(() => _currentPage = i),
                    children: pages,
                  ),
                ),

                // Dot indicators
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_pageCount, (i) {
                      final isActive = i == _currentPage;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xxs),
                        width: isActive ? 20 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: isActive
                              ? scheme.primary
                              : scheme.primary.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                ),

                // Bottom action button
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xl,
                    0,
                    AppSpacing.xl,
                    AppSpacing.lg,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: isLastPage ? _goHome : _nextPage,
                      child: Text(
                        isLastPage ? l10n.tourGetStarted : l10n.tourNext,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Single tour page ──────────────────────────────────────────────────────

class _TourPage extends StatelessWidget {
  const _TourPage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xl,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 112,
            height: 112,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 52, color: scheme.primary),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }
}
