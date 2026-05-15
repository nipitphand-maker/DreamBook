import 'package:shared_preferences/shared_preferences.dart';

import 'family_entry.dart';

const _kFamiliesListKey = 'families.list';
const _kFamilyIdKey = 'family.id';

class FamilyRepository {
  FamilyRepository(this._prefs);

  final SharedPreferences _prefs;

  /// All known families. Migrates from legacy `family.id` key on first call
  /// if `families.list` has never been written.
  List<FamilyEntry> list() {
    final raw = _prefs.getString(_kFamiliesListKey);
    if (raw != null) return FamilyEntry.listFromJson(raw);
    // Migration path: legacy format stored only the active id.
    final legacyId = _prefs.getString(_kFamilyIdKey) ?? '';
    if (legacyId.isEmpty) return [];
    return [
      FamilyEntry(
        id: legacyId,
        label: 'My Family',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      ),
    ];
  }

  /// The currently active family id (same as `family.id` prefs key).
  String? activeId() => _prefs.getString(_kFamilyIdKey);

  /// Appends [entry] to the list (no-op if id already present) and sets it
  /// as the active family.
  Future<void> register(FamilyEntry entry) async {
    final current = list();
    if (!current.any((e) => e.id == entry.id)) {
      final updated = [...current, entry];
      await _prefs.setString(_kFamiliesListKey, FamilyEntry.listToJson(updated));
    }
    await _prefs.setString(_kFamilyIdKey, entry.id);
  }

  /// Switches the active family to [familyId]. [familyId] must already be in
  /// the list — callers are responsible for validating.
  Future<void> switchTo(String familyId) async {
    await _prefs.setString(_kFamilyIdKey, familyId);
  }

  /// Removes [familyId] from the list. If it was the active family, switches
  /// to the first remaining family (or clears `family.id` if the list is now
  /// empty).
  Future<void> remove(String familyId) async {
    final updated = list().where((e) => e.id != familyId).toList();
    await _prefs.setString(_kFamiliesListKey, FamilyEntry.listToJson(updated));
    if (activeId() == familyId) {
      await _prefs.setString(_kFamilyIdKey, updated.isEmpty ? '' : updated.first.id);
    }
  }

  /// True if the user is allowed to create another family.
  /// Free tier: max 1 family. Premium: unlimited.
  bool canAddFamily({required bool isPremium, required int currentCount}) =>
      isPremium || currentCount == 0;
}
