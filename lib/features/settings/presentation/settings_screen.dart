import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/providers/premium_provider.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/core/providers/unit_preferences_provider.dart';
import 'package:dreambook/core/router/app_router.dart';
import 'package:dreambook/core/services/unit_preferences.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

const _kPortionOz = 'settings.pump.portionOz';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  double _portionOz = 4.0;

  @override
  void initState() {
    super.initState();
    _portionOz =
        ref.read(sharedPreferencesProvider).getDouble(_kPortionOz) ?? 4.0;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final prefs = ref.watch(unitPreferencesProvider);
    final notifier = ref.read(unitPreferencesProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          const _PremiumTile(),
          const _SectionHeader(title: 'Measurements'),
          _UnitTile<VolumeUnit>(
            label: 'Volume',
            selected: {prefs.volume},
            segments: const [
              ButtonSegment(value: VolumeUnit.oz, label: Text('oz')),
              ButtonSegment(value: VolumeUnit.ml, label: Text('ml')),
            ],
            onSelectionChanged: (s) => notifier.setVolume(s.first),
          ),
          _UnitTile<WeightUnit>(
            label: 'Weight',
            selected: {prefs.weight},
            segments: const [
              ButtonSegment(value: WeightUnit.lbOz, label: Text('lb + oz')),
              ButtonSegment(value: WeightUnit.kg, label: Text('kg')),
            ],
            onSelectionChanged: (s) => notifier.setWeight(s.first),
          ),
          _UnitTile<LengthUnit>(
            label: 'Length',
            selected: {prefs.length},
            segments: const [
              ButtonSegment(value: LengthUnit.inches, label: Text('in')),
              ButtonSegment(value: LengthUnit.cm, label: Text('cm')),
            ],
            onSelectionChanged: (s) => notifier.setLength(s.first),
          ),
          _UnitTile<TempUnit>(
            label: 'Temperature',
            selected: {prefs.temp},
            segments: const [
              ButtonSegment(value: TempUnit.fahrenheit, label: Text('°F')),
              ButtonSegment(value: TempUnit.celsius, label: Text('°C')),
            ],
            onSelectionChanged: (s) => notifier.setTemp(s.first),
          ),
          const _SectionHeader(title: 'Display'),
          _UnitTile<TimeFormat>(
            label: 'Time format',
            selected: {prefs.timeFormat},
            segments: const [
              ButtonSegment(value: TimeFormat.h12, label: Text('12h')),
              ButtonSegment(value: TimeFormat.h24, label: Text('24h')),
            ],
            onSelectionChanged: (s) => notifier.setTimeFormat(s.first),
          ),
          _UnitTile<WeekStart>(
            label: 'Week starts on',
            selected: {prefs.weekStart},
            segments: const [
              ButtonSegment(value: WeekStart.sunday, label: Text('Sun')),
              ButtonSegment(value: WeekStart.monday, label: Text('Mon')),
            ],
            onSelectionChanged: (s) => notifier.setWeekStart(s.first),
          ),
          const _SectionHeader(title: 'Pumping'),
          ListTile(
            title: const Text('Default bottle size'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: _portionOz <= 0.5
                      ? null
                      : () {
                          final next = double.parse(
                              (_portionOz - 0.5).toStringAsFixed(1));
                          setState(() => _portionOz = next);
                          ref
                              .read(sharedPreferencesProvider)
                              .setDouble(_kPortionOz, next);
                        },
                  icon: const Icon(Icons.remove),
                ),
                Text(
                  '${_portionOz.toStringAsFixed(1)} oz',
                  style: AppTypography.numeric(size: 14),
                ),
                IconButton(
                  onPressed: _portionOz >= 16.0
                      ? null
                      : () {
                          final next = double.parse(
                              (_portionOz + 0.5).toStringAsFixed(1));
                          setState(() => _portionOz = next);
                          ref
                              .read(sharedPreferencesProvider)
                              .setDouble(_kPortionOz, next);
                        },
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          const _SectionHeader(title: 'Health'),
          ListTile(
            leading: const Icon(Icons.vaccines_outlined),
            title: Text(l10n.settingsVaccinations),
            trailing: const Icon(Icons.chevron_right, color: AppColors.inkSecondary),
            onTap: () => context.push(AppRoutes.vaccination),
          ),
          const _SectionHeader(title: 'About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Version'),
            subtitle: Text('1.0.0 (build 1)'),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.open_in_new_outlined, size: 16),
            onTap: () {},
          ),
        ],
      ),
    );
  }
}

/// Top-of-settings premium upsell.
///
/// Non-premium users see a tappable "Get DreamBook Premium" ListTile that
/// routes to the paywall. Premium users see a non-tappable "Premium ✓ Active"
/// confirmation. While entitlement is loading, renders nothing.
class _PremiumTile extends ConsumerWidget {
  const _PremiumTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final premiumAsync = ref.watch(isPremiumProvider);

    return premiumAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (isPremium) {
        if (isPremium) {
          return ListTile(
            leading: const Icon(
              Icons.check_circle_outline,
              color: AppColors.sage700,
            ),
            title: Text(l10n.settingsPremiumActive),
          );
        }
        return ListTile(
          leading: const Icon(
            Icons.workspace_premium_outlined,
            color: AppColors.lavender700,
          ),
          title: Text(l10n.settingsPremiumCta),
          subtitle: Text(l10n.settingsPremiumSubtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(AppRoutes.premium),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Text(
        title,
        style: AppTypography.labelLarge(color: AppColors.lavender700),
      ),
    );
  }
}

class _UnitTile<T> extends StatelessWidget {
  const _UnitTile({
    required this.label,
    required this.selected,
    required this.segments,
    required this.onSelectionChanged,
    super.key,
  });

  final String label;
  final Set<T> selected;
  final List<ButtonSegment<T>> segments;
  final ValueChanged<Set<T>> onSelectionChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodyMedium(color: AppColors.inkPrimary),
            ),
          ),
          SegmentedButton<T>(
            segments: segments,
            selected: selected,
            onSelectionChanged: onSelectionChanged,
            showSelectedIcon: false,
          ),
        ],
      ),
    );
  }
}
