import 'package:dreambook/core/families/family_repository.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'family_entry.dart';

final familyRepositoryProvider = Provider<FamilyRepository>((ref) {
  return FamilyRepository(ref.watch(sharedPreferencesProvider));
});

class FamilyListNotifier extends Notifier<List<FamilyEntry>> {
  @override
  List<FamilyEntry> build() =>
      ref.read(familyRepositoryProvider).list();

  Future<void> register(FamilyEntry entry) async {
    await ref.read(familyRepositoryProvider).register(entry);
    state = ref.read(familyRepositoryProvider).list();
  }

  Future<void> switchTo(String familyId) async {
    await ref.read(familyRepositoryProvider).switchTo(familyId);
    // List contents unchanged; force rebuild so active-indicator re-evaluates.
    state = List.of(state);
  }

  Future<void> remove(String familyId) async {
    await ref.read(familyRepositoryProvider).remove(familyId);
    state = ref.read(familyRepositoryProvider).list();
  }
}

final familyListProvider =
    NotifierProvider<FamilyListNotifier, List<FamilyEntry>>(
        FamilyListNotifier.new);
