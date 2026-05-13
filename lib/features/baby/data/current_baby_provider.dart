import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _kCurrentBabyIdKey = 'current_baby_id';

class CurrentBabyIdNotifier extends Notifier<String?> {
  @override
  String? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getString(_kCurrentBabyIdKey);
  }

  Future<void> select(String babyId) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_kCurrentBabyIdKey, babyId);
    state = babyId;
  }

  Future<void> clear() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_kCurrentBabyIdKey);
    state = null;
  }
}

final currentBabyIdProvider =
    NotifierProvider<CurrentBabyIdNotifier, String?>(CurrentBabyIdNotifier.new);
