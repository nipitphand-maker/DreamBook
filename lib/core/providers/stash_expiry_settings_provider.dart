import 'package:dreambook/core/models/stash_bottle.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _kFreezerDays = 'stash_expiry.freezer_days';
const _kFridgeDays = 'stash_expiry.fridge_days';
const _kRoomHours = 'stash_expiry.room_hours';

class StashExpirySettings {
  const StashExpirySettings({
    this.freezerDays = 180,
    this.fridgeDays = 4,
    this.roomHours = 4,
  });

  final int freezerDays;
  final int fridgeDays;
  final int roomHours;

  Duration shelfLifeFor(StorageType storage) => switch (storage) {
        StorageType.freezer => Duration(days: freezerDays),
        StorageType.fridge => Duration(days: fridgeDays),
        StorageType.room => Duration(hours: roomHours),
      };

  StashExpirySettings copyWith({
    int? freezerDays,
    int? fridgeDays,
    int? roomHours,
  }) =>
      StashExpirySettings(
        freezerDays: freezerDays ?? this.freezerDays,
        fridgeDays: fridgeDays ?? this.fridgeDays,
        roomHours: roomHours ?? this.roomHours,
      );
}

class StashExpirySettingsNotifier extends Notifier<StashExpirySettings> {
  @override
  StashExpirySettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return StashExpirySettings(
      freezerDays: prefs.getInt(_kFreezerDays) ?? 180,
      fridgeDays: prefs.getInt(_kFridgeDays) ?? 4,
      roomHours: prefs.getInt(_kRoomHours) ?? 4,
    );
  }

  void setFreezerDays(int days) {
    ref.read(sharedPreferencesProvider).setInt(_kFreezerDays, days);
    state = state.copyWith(freezerDays: days);
  }

  void setFridgeDays(int days) {
    ref.read(sharedPreferencesProvider).setInt(_kFridgeDays, days);
    state = state.copyWith(fridgeDays: days);
  }

  void setRoomHours(int hours) {
    ref.read(sharedPreferencesProvider).setInt(_kRoomHours, hours);
    state = state.copyWith(roomHours: hours);
  }
}

final stashExpirySettingsProvider =
    NotifierProvider<StashExpirySettingsNotifier, StashExpirySettings>(
  StashExpirySettingsNotifier.new,
);
