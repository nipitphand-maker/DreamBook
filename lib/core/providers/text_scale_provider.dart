import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _kTextScaleKey = 'settings.textScale';

enum AppTextScale { small, normal, large }

extension AppTextScaleX on AppTextScale {
  double get factor => switch (this) {
        AppTextScale.small => 0.85,
        AppTextScale.normal => 1.0,
        AppTextScale.large => 1.15,
      };
}

class TextScaleNotifier extends Notifier<AppTextScale> {
  @override
  AppTextScale build() {
    final v = ref.read(sharedPreferencesProvider).getString(_kTextScaleKey);
    return switch (v) {
      'small' => AppTextScale.small,
      'large' => AppTextScale.large,
      _ => AppTextScale.normal,
    };
  }

  Future<void> set(AppTextScale scale) async {
    await ref
        .read(sharedPreferencesProvider)
        .setString(_kTextScaleKey, scale.name);
    state = scale;
  }
}

final textScaleProvider =
    NotifierProvider<TextScaleNotifier, AppTextScale>(TextScaleNotifier.new);
