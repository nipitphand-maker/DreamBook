import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/providers/crash_reporting_provider.dart';
import 'package:dreambook/core/providers/day_start_hour_provider.dart';
import 'package:dreambook/core/providers/premium_provider.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/core/providers/unit_preferences_provider.dart';
import 'package:dreambook/core/router/app_router.dart';
import 'package:dreambook/core/services/feed_alert_service.dart';
import 'package:dreambook/core/services/unit_preferences.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/core/providers/locale_provider.dart';
import 'package:dreambook/core/providers/text_scale_provider.dart';
import 'package:dreambook/core/theme/theme_mode_controller.dart';
import 'package:dreambook/features/baby/data/baby_repository.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:dreambook/features/baby/presentation/add_baby_screen.dart';
import 'package:dreambook/features/feed/data/feed_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

const _kPortionOz = 'settings.pump.portionOz';
const _mlPerOz = 29.5735;
const _privacyPolicyUrl = 'https://nipitphand-maker.github.io/DreamBook/privacy-policy/';

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

  /// Formats an hour (0–23) as a human-readable AM/PM string.
  String _formatHour(int hour) {
    if (hour == 0) return '12:00 AM';
    if (hour < 12) return '$hour:00 AM';
    if (hour == 12) return '12:00 PM';
    return '${hour - 12}:00 PM';
  }

  Future<void> _showDayStartDialog() async {
    const options = [0, 3, 5, 6, 7, 8];
    final currentHour = ref.read(dayStartHourProvider);
    final selected = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(context.l10n.settingsDayStart),
        children: options
            .map(
              (h) => ListTile(
                title: Text(_formatHour(h)),
                trailing: h == currentHour
                    ? Icon(
                        Icons.check,
                        color: Theme.of(ctx).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.of(ctx).pop(h),
              ),
            )
            .toList(),
      ),
    );
    if (selected == null || !mounted) return;
    await ref.read(sharedPreferencesProvider).setInt(kDayStartHour, selected);
    // sharedPreferencesProvider is a plain Provider whose value (the
    // SharedPreferences instance) never changes identity, so Riverpod will not
    // automatically recompute dayStartHourProvider when the underlying pref
    // value changes. We invalidate dayStartHourProvider explicitly so that all
    // *TodayNotifier.build() calls re-run with the new hour.
    ref.invalidate(dayStartHourProvider);
  }

  Future<void> _launchPrivacy() async {
    final uri = Uri.parse(_privacyPolicyUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.settingsPrivacyError)),
      );
    }
  }

  Future<void> _editBabyProfile() async {
    final baby = await ref.read(babyRepositoryProvider).getActive();
    if (baby == null || !mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AddBabyScreen(baby: baby)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final prefs = ref.watch(unitPreferencesProvider);
    final notifier = ref.read(unitPreferencesProvider.notifier);
    final themeChoice =
        ref.watch(themeModeControllerProvider).value?.choice ??
            UserThemeChoice.system;
    final themeNotifier = ref.read(themeModeControllerProvider.notifier);
    final locale = ref.watch(localeProvider);
    final localeCode = locale?.languageCode ?? 'system';
    final localeNotifier = ref.read(localeProvider.notifier);
    final textScale = ref.watch(textScaleProvider);
    final textScaleNotifier = ref.read(textScaleProvider.notifier);
    final babyId = ref.watch(currentBabyIdProvider);
    final dayStartHour = ref.watch(dayStartHourProvider);

    final portionDisplay = prefs.volume == VolumeUnit.oz
        ? '${_portionOz.toStringAsFixed(1)} oz'
        : '${(_portionOz * _mlPerOz).round()} ml';
    final portionStep = prefs.volume == VolumeUnit.oz ? 0.5 : 5 / _mlPerOz;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(l10n.tabSettings),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        children: [
          const _PremiumTile(),
          _SectionHeader(title: l10n.settingsSectionBabyProfile),
          ListTile(
            leading: const Icon(Icons.child_care_outlined),
            title: Text(l10n.settingsEditBabyProfile),
            trailing: const Icon(Icons.chevron_right),
            enabled: babyId != null,
            onTap: babyId == null ? null : _editBabyProfile,
          ),
          _SectionHeader(title: l10n.settingsSectionMeasurements),
          _UnitTile<VolumeUnit>(
            label: l10n.settingsVolumeLabel,
            selected: {prefs.volume},
            segments: const [
              ButtonSegment(value: VolumeUnit.oz, label: Text('oz')),
              ButtonSegment(value: VolumeUnit.ml, label: Text('ml')),
            ],
            onSelectionChanged: (s) => notifier.setVolume(s.first),
          ),
          _UnitTile<WeightUnit>(
            label: l10n.settingsWeightLabel,
            selected: {prefs.weight},
            segments: const [
              ButtonSegment(value: WeightUnit.lbOz, label: Text('lb + oz')),
              ButtonSegment(value: WeightUnit.kg, label: Text('kg')),
            ],
            onSelectionChanged: (s) => notifier.setWeight(s.first),
          ),
          _UnitTile<LengthUnit>(
            label: l10n.settingsLengthLabel,
            selected: {prefs.length},
            segments: const [
              ButtonSegment(value: LengthUnit.inches, label: Text('in')),
              ButtonSegment(value: LengthUnit.cm, label: Text('cm')),
            ],
            onSelectionChanged: (s) => notifier.setLength(s.first),
          ),
          _UnitTile<TempUnit>(
            label: l10n.settingsTempLabel,
            selected: {prefs.temp},
            segments: const [
              ButtonSegment(value: TempUnit.fahrenheit, label: Text('°F')),
              ButtonSegment(value: TempUnit.celsius, label: Text('°C')),
            ],
            onSelectionChanged: (s) => notifier.setTemp(s.first),
          ),
          _SectionHeader(title: l10n.settingsSectionDisplay),
          _UnitTile<TimeFormat>(
            label: l10n.settingsTimeFormatLabel,
            selected: {prefs.timeFormat},
            segments: const [
              ButtonSegment(value: TimeFormat.h12, label: Text('12h')),
              ButtonSegment(value: TimeFormat.h24, label: Text('24h')),
            ],
            onSelectionChanged: (s) => notifier.setTimeFormat(s.first),
          ),
          _UnitTile<WeekStart>(
            label: l10n.settingsWeekStartLabel,
            selected: {prefs.weekStart},
            segments: const [
              ButtonSegment(value: WeekStart.sunday, label: Text('Sun')),
              ButtonSegment(value: WeekStart.monday, label: Text('Mon')),
            ],
            onSelectionChanged: (s) => notifier.setWeekStart(s.first),
          ),
          ListTile(
            leading: const Icon(Icons.schedule_outlined),
            title: Text(l10n.settingsDayStart),
            subtitle: Text(l10n.settingsDayStartSubtitle),
            trailing: Text(
              _formatHour(dayStartHour),
              style: AppTypography.numeric(size: 14),
            ),
            onTap: _showDayStartDialog,
          ),
          _UnitTile<UserThemeChoice>(
            label: l10n.settingsThemeLabel,
            selected: {themeChoice},
            segments: [
              ButtonSegment(
                value: UserThemeChoice.system,
                label: Text(l10n.settingsThemeSystem),
              ),
              ButtonSegment(
                value: UserThemeChoice.light,
                label: Text(l10n.settingsThemeLight),
              ),
              ButtonSegment(
                value: UserThemeChoice.dark,
                label: Text(l10n.settingsThemeDark),
              ),
              ButtonSegment(
                value: UserThemeChoice.nightTint,
                label: Text(l10n.settingsThemeNight),
              ),
            ],
            onSelectionChanged: (s) => themeNotifier.setChoice(s.first),
          ),
          _UnitTile<String>(
            label: l10n.settingsLanguage,
            selected: {localeCode},
            segments: [
              ButtonSegment(
                value: 'system',
                label: Text(l10n.settingsThemeSystem),
              ),
              ButtonSegment(
                value: 'en',
                label: Text(l10n.settingsLanguageEn),
              ),
              ButtonSegment(
                value: 'th',
                label: Text(l10n.settingsLanguageTh),
              ),
            ],
            onSelectionChanged: (s) {
              final v = s.first;
              localeNotifier.setLocale(v == 'system' ? null : Locale(v));
            },
          ),
          _UnitTile<AppTextScale>(
            label: l10n.settingsTextSizeLabel,
            selected: {textScale},
            segments: [
              ButtonSegment(
                value: AppTextScale.small,
                label: Text(l10n.settingsTextSmall),
              ),
              ButtonSegment(
                value: AppTextScale.normal,
                label: Text(l10n.settingsTextNormal),
              ),
              ButtonSegment(
                value: AppTextScale.large,
                label: Text(l10n.settingsTextLarge),
              ),
            ],
            onSelectionChanged: (s) => textScaleNotifier.set(s.first),
          ),
          _SectionHeader(title: l10n.settingsSectionPumping),
          const _FeedAlertTile(),
          ListTile(
            title: Text(l10n.settingsBottleSizeLabel),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: _portionOz <= 0.5
                      ? null
                      : () {
                          final next =
                              (_portionOz - portionStep).clamp(0.5, 16.0);
                          final stored = prefs.volume == VolumeUnit.oz
                              ? double.parse(next.toStringAsFixed(1))
                              : next;
                          setState(() => _portionOz = stored);
                          ref
                              .read(sharedPreferencesProvider)
                              .setDouble(_kPortionOz, stored);
                        },
                  icon: const Icon(Icons.remove),
                ),
                Text(
                  portionDisplay,
                  style: AppTypography.numeric(size: 14),
                ),
                IconButton(
                  onPressed: _portionOz >= 16.0
                      ? null
                      : () {
                          final next =
                              (_portionOz + portionStep).clamp(0.5, 16.0);
                          final stored = prefs.volume == VolumeUnit.oz
                              ? double.parse(next.toStringAsFixed(1))
                              : next;
                          setState(() => _portionOz = stored);
                          ref
                              .read(sharedPreferencesProvider)
                              .setDouble(_kPortionOz, stored);
                        },
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          _SectionHeader(title: l10n.settingsSectionHealth),
          ListTile(
            leading: const Icon(Icons.vaccines_outlined),
            title: Text(l10n.settingsVaccinations),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.vaccination),
          ),
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined),
            title: Text(l10n.settingsVisitReport),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.visitReport),
          ),
          _SectionHeader(title: l10n.settingsSectionSecurity),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: Text(context.l10n.recoveryUxCloudBackupTitle),
            subtitle: Text(context.l10n.settingsCloudBackupSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.cloudBackup),
          ),
          ListTile(
            leading: const Icon(Icons.devices),
            title: Text(context.l10n.settingsManageDevicesTitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.manageDevices),
          ),
          _SectionHeader(title: l10n.recoveryUxAdvancedSectionTitle),
          Consumer(
            builder: (context, ref, _) {
              final prefs = ref.watch(sharedPreferencesProvider);
              final backed = prefs.getBool('recovery.phrase_backed_up') ?? false;
              final scheme = Theme.of(context).colorScheme;
              return ListTile(
                leading: Icon(
                  backed ? Icons.lock : Icons.lock_open,
                  color: backed ? scheme.primary : scheme.error,
                ),
                title: Text(context.l10n.recoveryUxAdvancedRecoveryPhraseTitle),
                subtitle: Text(
                  backed
                      ? context.l10n.settingsRecoveryPhraseBackedUp
                      : context.l10n.settingsRecoveryPhraseNotBackedUp,
                  style: TextStyle(color: backed ? null : scheme.error),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.bip39Setup),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.group_outlined),
            title: Text(l10n.settingsFamiliesTitle),
            subtitle: Text(l10n.settingsFamiliesSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.families),
          ),
          _SectionHeader(title: l10n.settingsSectionAbout),
          SwitchListTile(
            secondary: const Icon(Icons.bug_report_outlined),
            title: Text(l10n.settingsCrashReporting),
            subtitle: Text(l10n.settingsCrashReportingSubtitle),
            value: ref.watch(crashReportingEnabledProvider),
            onChanged: (v) =>
                ref.read(crashReportingNotifierProvider).setEnabled(v),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(l10n.settingsVersion),
            subtitle: const Text('1.0.0 (build 1)'),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(l10n.settingsPrivacyPolicy),
            trailing: const Icon(Icons.open_in_new_outlined, size: 16),
            onTap: _launchPrivacy,
          ),
        ],
      ),
    );
  }
}

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
            color: AppColors.peach700,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Text(
        title,
        style: AppTypography.labelLarge(
          color: isDark
              ? Theme.of(context).colorScheme.primary
              : AppColors.lavender700,
        ),
      ),
    );
  }
}

class _FeedAlertTile extends ConsumerStatefulWidget {
  const _FeedAlertTile();

  @override
  ConsumerState<_FeedAlertTile> createState() => _FeedAlertTileState();
}

class _FeedAlertTileState extends ConsumerState<_FeedAlertTile> {
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(sharedPreferencesProvider);
    _enabled = prefs.getBool(FeedAlertService.enabledKey) ?? true;
  }

  Future<void> _toggle(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final l10n = context.l10n;
    await prefs.setBool(FeedAlertService.enabledKey, value);
    setState(() => _enabled = value);

    if (!value) {
      await FeedAlertService.cancel();
      return;
    }

    final babyId = ref.read(currentBabyIdProvider);
    if (babyId == null) return;

    final lastFeed =
        await ref.read(feedRepositoryProvider).getLastFeedForBaby(babyId);
    final intervalHours = prefs.getInt(FeedAlertService.prefsKey) ?? 3;
    final baby = await ref.read(babyRepositoryProvider).getActive();
    final babyName = baby?.nickname?.isNotEmpty == true
        ? baby!.nickname!
        : (baby?.name ?? '');

    if (!mounted) return;
    await FeedAlertService.scheduleForLastFeed(
      prefs: prefs,
      lastFeed: lastFeed,
      title: l10n.feedAlertNotifTitle,
      body: babyName.isEmpty
          ? l10n.feedAlertSettingSubtitle(intervalHours)
          : l10n.feedAlertNotifBody(babyName, intervalHours),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final prefs = ref.read(sharedPreferencesProvider);
    final intervalHours = prefs.getInt(FeedAlertService.prefsKey) ?? 3;

    return SwitchListTile(
      secondary: const Icon(Icons.notifications_outlined),
      title: Text(l10n.feedAlertSettingTitle),
      subtitle: Text(l10n.feedAlertSettingSubtitle(intervalHours)),
      value: _enabled,
      onChanged: _toggle,
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
              style: AppTypography.bodyMedium(
                color: Theme.of(context).colorScheme.onSurface,
              ),
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
