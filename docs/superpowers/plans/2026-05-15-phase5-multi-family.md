# Phase 5 — Multi-Family + Premium Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users manage multiple family groups (premium-gated), show a family picker on Home when count > 1, and gate second-family creation behind the RevenueCat `premium` entitlement.

**Architecture:** A new `FamilyRepository` owns a `families.list` JSON blob in SharedPreferences alongside the existing `family.id` active-pointer key. All family mutations go through `FamilyRepository`; a `familyListProvider` Notifier keeps the UI reactive. The sync system already uses `family.id` as-is — switching families writes a new value to that key and invalidates `syncLifecycleControllerProvider`.

**Tech stack:** Flutter, Riverpod 3 (hand-rolled Notifier — no codegen), SharedPreferences, Supabase Edge Functions (`bootstrap_family`), RevenueCat (`isPremiumProvider`), go_router.

---

## File map

| Action | Path | Purpose |
|---|---|---|
| Create | `lib/core/families/family_entry.dart` | `FamilyEntry` data class (id, label, createdAt) |
| Create | `lib/core/families/family_repository.dart` | Manages `families.list` + migration from `family.id` |
| Create | `lib/core/families/family_provider.dart` | `familyRepositoryProvider` + `familyListProvider` Notifier |
| Create | `lib/features/families/presentation/families_screen.dart` | List · switch · leave · add-another UI |
| Create | `test/core/families/family_repository_test.dart` | Unit tests for repository logic |
| Modify | `lib/core/router/app_router.dart` | Add `AppRoutes.families = '/settings/families'` + route |
| Modify | `lib/features/settings/presentation/settings_screen.dart` | "Families" tile in Security section |
| Modify | `lib/features/home/presentation/home_screen.dart` | `_FamilyBanner` shown when family count > 1 |
| Modify | `lib/features/onboarding/presentation/welcome_screen.dart` | Register family in `FamilyRepository` after bootstrap |
| Modify | `lib/features/onboarding/presentation/bip39_restore_screen.dart` | Register family after restore |
| Modify | `lib/features/share/presentation/claim_invite_screen.dart` | Register family after claiming invite |
| Modify | `lib/features/share/presentation/share_invite_screen.dart` | Register family after bootstrap in `_ensureFamily()` |
| Modify | `lib/features/baby/data/baby_repository.dart` | Filter `list()` + `getActive()` by active `family_id` |
| Modify | `lib/l10n/app_en.arb` | New `families*` + `settingsFamilies*` + `homeFamilyBanner` keys |
| Modify | `lib/l10n/app_th.arb` | Thai equivalents |

---

## Task 1 — `FamilyEntry` data class

**Files:**
- Create: `lib/core/families/family_entry.dart`

- [ ] **Step 1: Create `family_entry.dart`**

```dart
import 'dart:convert';

class FamilyEntry {
  const FamilyEntry({
    required this.id,
    required this.label,
    required this.createdAt,
  });

  final String id;
  final String label;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'createdAt': createdAt.toIso8601String(),
      };

  factory FamilyEntry.fromJson(Map<String, dynamic> j) => FamilyEntry(
        id: j['id'] as String,
        label: j['label'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );

  static List<FamilyEntry> listFromJson(String raw) {
    final list = jsonDecode(raw) as List;
    return list.map((e) => FamilyEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  static String listToJson(List<FamilyEntry> entries) =>
      jsonEncode(entries.map((e) => e.toJson()).toList());
}
```

- [ ] **Step 2: Commit**

```bash
git add lib/core/families/family_entry.dart
git commit -m "feat(families): FamilyEntry data class with JSON round-trip"
```

---

## Task 2 — `FamilyRepository`

**Files:**
- Create: `lib/core/families/family_repository.dart`
- Create: `test/core/families/family_repository_test.dart`

### 2a — Write the tests first

- [ ] **Step 1: Create the test file**

```dart
import 'dart:convert';

import 'package:dreambook/core/families/family_entry.dart';
import 'package:dreambook/core/families/family_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

FamilyRepository makeRepo(Map<String, Object> initial) {
  SharedPreferences.setMockInitialValues(initial);
  // ignore: invalid_use_of_visible_for_testing_member
  final prefs = SharedPreferencesStorePlatform.instance.keys;
  // Use the async constructor so the in-memory store is populated
  // before we call synchronous getters.
  return FamilyRepository._testOnly(
    getString: (k) => initial[k] as String?,
    setString: (k, v) => initial[k] = v,
    remove: (k) => initial.remove(k),
  );
}
```

Wait — SharedPreferences can't be used with a raw sync fake like that. Use `SharedPreferences.setMockInitialValues` then `await SharedPreferences.getInstance()`. Use the async factory pattern:

```dart
import 'package:dreambook/core/families/family_entry.dart';
import 'package:dreambook/core/families/family_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<FamilyRepository> makeRepo([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  return FamilyRepository(prefs);
}

void main() {
  group('FamilyRepository.list()', () {
    test('returns empty list when no data', () async {
      final repo = await makeRepo();
      expect(repo.list(), isEmpty);
    });

    test('migrates legacy family.id into a single-entry list', () async {
      final repo = await makeRepo({'family.id': 'abc-123'});
      final list = repo.list();
      expect(list, hasLength(1));
      expect(list.first.id, 'abc-123');
      expect(list.first.label, 'My Family');
    });

    test('returns all registered families from families.list', () async {
      final entry = FamilyEntry(id: 'f1', label: 'Test Family', createdAt: DateTime(2026));
      final repo = await makeRepo({
        'families.list': FamilyEntry.listToJson([entry]),
        'family.id': 'f1',
      });
      final list = repo.list();
      expect(list, hasLength(1));
      expect(list.first.id, 'f1');
    });
  });

  group('FamilyRepository.activeId()', () {
    test('returns null when family.id not set', () async {
      final repo = await makeRepo();
      expect(repo.activeId(), isNull);
    });

    test('returns family.id value', () async {
      final repo = await makeRepo({'family.id': 'xyz'});
      expect(repo.activeId(), 'xyz');
    });
  });

  group('FamilyRepository.register()', () {
    test('adds entry to list and sets active id', () async {
      final repo = await makeRepo();
      final entry = FamilyEntry(id: 'f1', label: 'Emma\'s Family', createdAt: DateTime(2026));
      await repo.register(entry);
      expect(repo.list(), hasLength(1));
      expect(repo.activeId(), 'f1');
    });

    test('is idempotent — registering same id twice stays at length 1', () async {
      final repo = await makeRepo();
      final entry = FamilyEntry(id: 'f1', label: 'Test', createdAt: DateTime(2026));
      await repo.register(entry);
      await repo.register(entry);
      expect(repo.list(), hasLength(1));
    });
  });

  group('FamilyRepository.switchTo()', () {
    test('updates activeId without changing list', () async {
      final e1 = FamilyEntry(id: 'f1', label: 'Family 1', createdAt: DateTime(2026));
      final e2 = FamilyEntry(id: 'f2', label: 'Family 2', createdAt: DateTime(2026));
      final repo = await makeRepo({
        'families.list': FamilyEntry.listToJson([e1, e2]),
        'family.id': 'f1',
      });
      await repo.switchTo('f2');
      expect(repo.activeId(), 'f2');
      expect(repo.list(), hasLength(2));
    });
  });

  group('FamilyRepository.remove()', () {
    test('removes entry from list', () async {
      final e1 = FamilyEntry(id: 'f1', label: 'Family 1', createdAt: DateTime(2026));
      final e2 = FamilyEntry(id: 'f2', label: 'Family 2', createdAt: DateTime(2026));
      final repo = await makeRepo({
        'families.list': FamilyEntry.listToJson([e1, e2]),
        'family.id': 'f2',
      });
      await repo.remove('f1');
      expect(repo.list(), hasLength(1));
      expect(repo.list().first.id, 'f2');
      expect(repo.activeId(), 'f2');
    });

    test('switches active to first remaining when removing the active family', () async {
      final e1 = FamilyEntry(id: 'f1', label: 'Family 1', createdAt: DateTime(2026));
      final e2 = FamilyEntry(id: 'f2', label: 'Family 2', createdAt: DateTime(2026));
      final repo = await makeRepo({
        'families.list': FamilyEntry.listToJson([e1, e2]),
        'family.id': 'f1',
      });
      await repo.remove('f1');
      expect(repo.list(), hasLength(1));
      expect(repo.activeId(), 'f2');
    });

    test('clears activeId when removing the only family', () async {
      final e1 = FamilyEntry(id: 'f1', label: 'Family 1', createdAt: DateTime(2026));
      final repo = await makeRepo({
        'families.list': FamilyEntry.listToJson([e1]),
        'family.id': 'f1',
      });
      await repo.remove('f1');
      expect(repo.list(), isEmpty);
      expect(repo.activeId(), isEmpty);
    });
  });

  group('FamilyRepository.canAddFamily()', () {
    test('free user with 0 families: allowed', () async {
      final repo = await makeRepo();
      expect(repo.canAddFamily(isPremium: false, currentCount: 0), isTrue);
    });

    test('free user with 1 family: blocked', () async {
      final repo = await makeRepo();
      expect(repo.canAddFamily(isPremium: false, currentCount: 1), isFalse);
    });

    test('premium user with 1 family: allowed', () async {
      final repo = await makeRepo();
      expect(repo.canAddFamily(isPremium: true, currentCount: 1), isTrue);
    });

    test('premium user with 5 families: allowed', () async {
      final repo = await makeRepo();
      expect(repo.canAddFamily(isPremium: true, currentCount: 5), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run tests — expect compile error (class not defined yet)**

```bash
flutter test test/core/families/family_repository_test.dart
```

Expected output: compilation failure mentioning `FamilyRepository` not found.

### 2b — Implement FamilyRepository

- [ ] **Step 3: Create `family_repository.dart`**

```dart
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
```

- [ ] **Step 4: Run tests — expect all green**

```bash
flutter test test/core/families/family_repository_test.dart
```

Expected: `All tests passed` (12 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/core/families/family_entry.dart lib/core/families/family_repository.dart test/core/families/family_repository_test.dart
git commit -m "feat(families): FamilyRepository with list/register/switch/remove/migrate"
```

---

## Task 3 — `familyRepositoryProvider` + `familyListProvider`

**Files:**
- Create: `lib/core/families/family_provider.dart`

- [ ] **Step 1: Create the provider file**

```dart
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
```

- [ ] **Step 2: Verify analysis**

```bash
flutter analyze lib/core/families/
```

Expected: no errors, no warnings.

- [ ] **Step 3: Commit**

```bash
git add lib/core/families/family_provider.dart
git commit -m "feat(families): familyRepositoryProvider + familyListProvider Notifier"
```

---

## Task 4 — Register family in all onboarding + share flows

**Files:**
- Modify: `lib/features/onboarding/presentation/welcome_screen.dart` (around line 100)
- Modify: `lib/features/onboarding/presentation/bip39_restore_screen.dart` (around line 117)
- Modify: `lib/features/share/presentation/claim_invite_screen.dart` (around line 112)
- Modify: `lib/features/share/presentation/share_invite_screen.dart` (around line 143)

Each change adds two lines immediately after the existing `prefs.setString(_kFamilyIdKey, familyId)` call: import the provider and call `familyListProvider.notifier.register()`.

### 4a — `welcome_screen.dart`

- [ ] **Step 1: Add import near top of file (after existing imports)**

In `welcome_screen.dart` add:
```dart
import '../../../core/families/family_entry.dart';
import '../../../core/families/family_provider.dart';
```

- [ ] **Step 2: In `_bootstrapFamily()`, after the existing `await prefs.setString(_kFamilyIdKey, familyId);` line, add registration**

Find this block (around line 99–101):
```dart
      final familyId = data['family_id'] as String;
      await prefs.setString(_kFamilyIdKey, familyId);
      await FamilyKeyService(_secureStorage).generate(
```

Replace with:
```dart
      final familyId = data['family_id'] as String;
      await prefs.setString(_kFamilyIdKey, familyId);
      final babyName = (await ref.read(babyRepositoryProvider).getActive())?.name ?? 'Baby';
      await ref.read(familyListProvider.notifier).register(FamilyEntry(
        id: familyId,
        label: "$babyName's Family",
        createdAt: DateTime.now().toUtc(),
      ));
      await FamilyKeyService(_secureStorage).generate(
```

### 4b — `bip39_restore_screen.dart`

- [ ] **Step 3: Add import**

```dart
import '../../../core/families/family_entry.dart';
import '../../../core/families/family_provider.dart';
```

- [ ] **Step 4: After `await prefs.setString(_kFamilyIdKey, familyId);` (line ~117), add**

```dart
      await ref.read(familyListProvider.notifier).register(FamilyEntry(
        id: familyId,
        label: 'Restored Family',
        createdAt: DateTime.now().toUtc(),
      ));
```

### 4c — `claim_invite_screen.dart`

- [ ] **Step 5: Add import**

```dart
import '../../../core/families/family_entry.dart';
import '../../../core/families/family_provider.dart';
```

- [ ] **Step 6: After `await prefs.setString(_kFamilyIdKey, familyId);` (line ~112), add**

```dart
      await ref.read(familyListProvider.notifier).register(FamilyEntry(
        id: familyId,
        label: 'Joined Family',
        createdAt: DateTime.now().toUtc(),
      ));
```

### 4d — `share_invite_screen.dart`

- [ ] **Step 7: Add import**

```dart
import '../../../core/families/family_entry.dart';
import '../../../core/families/family_provider.dart';
```

- [ ] **Step 8: In `_ensureFamily()`, after `await prefs.setString(_kFamilyIdKey, familyId);` (line ~143), add**

```dart
      await ref.read(familyListProvider.notifier).register(FamilyEntry(
        id: familyId,
        label: 'My Family',
        createdAt: DateTime.now().toUtc(),
      ));
```

- [ ] **Step 9: Verify compilation**

```bash
flutter analyze lib/features/onboarding/ lib/features/share/
```

Expected: no errors.

- [ ] **Step 10: Run all unit tests**

```bash
flutter test
```

Expected: all passing (at least 305 before this PR).

- [ ] **Step 11: Commit**

```bash
git add lib/features/onboarding/presentation/welcome_screen.dart \
        lib/features/onboarding/presentation/bip39_restore_screen.dart \
        lib/features/share/presentation/claim_invite_screen.dart \
        lib/features/share/presentation/share_invite_screen.dart
git commit -m "feat(families): register family in all onboarding + share bootstrap paths"
```

---

## Task 5 — Filter `BabyRepository.list()` + `getActive()` by active `family_id`

**Files:**
- Modify: `lib/features/baby/data/baby_repository.dart`

When a user switches families, the app should only show babies belonging to the active family. Currently `list()` returns all non-deleted babies regardless of `family_id`.

- [ ] **Step 1: Update `list()` — add `family_id` WHERE clause when family is set**

Find (around line 100):
```dart
  Future<List<Baby>> list() async {
    final db = await _db;
    final rows = await db.query(
      'baby',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at ASC',
    );
    return rows.map(Baby.fromRow).toList(growable: false);
  }
```

Replace with:
```dart
  Future<List<Baby>> list() async {
    final db = await _db;
    final familyId =
        _ref.read(sharedPreferencesProvider).getString('family.id') ?? '';
    final (where, whereArgs) = familyId.isEmpty
        ? ('deleted_at IS NULL', <Object?>[])
        : ('deleted_at IS NULL AND family_id = ?', [familyId]);
    final rows = await db.query(
      'baby',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'created_at ASC',
    );
    return rows.map(Baby.fromRow).toList(growable: false);
  }
```

- [ ] **Step 2: Update `getActive()` — filter first baby query by family_id**

Find (around line 87):
```dart
  Future<Baby?> getActive() async {
    final db = await _db;
    final rows = await db.query(
      'baby',
      where: 'deleted_at IS NULL',
      orderBy: 'created_at ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Baby.fromRow(rows.first);
  }
```

Replace with:
```dart
  Future<Baby?> getActive() async {
    final db = await _db;
    final familyId =
        _ref.read(sharedPreferencesProvider).getString('family.id') ?? '';
    final (where, whereArgs) = familyId.isEmpty
        ? ('deleted_at IS NULL', <Object?>[])
        : ('deleted_at IS NULL AND family_id = ?', [familyId]);
    final rows = await db.query(
      'baby',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'created_at ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Baby.fromRow(rows.first);
  }
```

- [ ] **Step 3: Add missing import at top of `baby_repository.dart`**

`shared_preferences_provider` is already imported via `sync_lifecycle_controller.dart`? Check: `import 'package:dreambook/core/providers/shared_preferences_provider.dart';` — if not present, add it.

```bash
grep "shared_preferences_provider" lib/features/baby/data/baby_repository.dart
```

If not found, add at top of imports:
```dart
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
```

- [ ] **Step 4: Verify analysis + tests**

```bash
flutter analyze lib/features/baby/
flutter test
```

Expected: no errors, all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/baby/data/baby_repository.dart
git commit -m "feat(families): filter BabyRepository list/getActive by active family_id"
```

---

## Task 6 — l10n keys

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_th.arb`

- [ ] **Step 1: Add English keys to `app_en.arb` — append before the closing `}`**

Find the last key before `}` and add after it:

```json
  "settingsFamiliesTitle": "Families",
  "settingsFamiliesSubtitle": "Manage your family groups",
  "familiesTitle": "Families",
  "familiesEmpty": "No families found.",
  "familiesActive": "Active",
  "familiesSwitch": "Switch to this family",
  "familiesLeave": "Leave",
  "familiesLeaveConfirmTitle": "Leave this family?",
  "familiesLeaveConfirmBody": "You'll lose access to this family's data on this device. This cannot be undone.",
  "familiesLeaveConfirmCta": "Leave",
  "familiesLeaveCancel": "Cancel",
  "familiesAddAnother": "Add Another Family",
  "familiesAddPremiumBody": "Managing multiple families requires DreamBook Premium.",
  "familiesCreating": "Creating family…",
  "familiesCreated": "Family created",
  "familiesCreatedError": "Could not create family. Check your connection and try again.",
  "homeFamilyBanner": "Family: {name}",
  "@homeFamilyBanner": {
    "placeholders": { "name": { "type": "String" } }
  }
```

- [ ] **Step 2: Add Thai keys to `app_th.arb` — same position**

```json
  "settingsFamiliesTitle": "ครอบครัว",
  "settingsFamiliesSubtitle": "จัดการกลุ่มครอบครัวของคุณ",
  "familiesTitle": "ครอบครัว",
  "familiesEmpty": "ไม่พบครอบครัว",
  "familiesActive": "ใช้งานอยู่",
  "familiesSwitch": "เปลี่ยนไปใช้ครอบครัวนี้",
  "familiesLeave": "ออก",
  "familiesLeaveConfirmTitle": "ออกจากครอบครัวนี้?",
  "familiesLeaveConfirmBody": "คุณจะสูญเสียการเข้าถึงข้อมูลครอบครัวนี้บนอุปกรณ์นี้ ไม่สามารถย้อนกลับได้",
  "familiesLeaveConfirmCta": "ออก",
  "familiesLeaveCancel": "ยกเลิก",
  "familiesAddAnother": "เพิ่มครอบครัวอื่น",
  "familiesAddPremiumBody": "การจัดการหลายครอบครัวต้องการ DreamBook พรีเมียม",
  "familiesCreating": "กำลังสร้างครอบครัว…",
  "familiesCreated": "สร้างครอบครัวสำเร็จ",
  "familiesCreatedError": "ไม่สามารถสร้างครอบครัวได้ กรุณาตรวจสอบการเชื่อมต่อแล้วลองอีกครั้ง",
  "homeFamilyBanner": "ครอบครัว: {name}",
  "@homeFamilyBanner": {
    "placeholders": { "name": { "type": "String" } }
  }
```

- [ ] **Step 3: Regenerate l10n**

```bash
flutter gen-l10n
```

Expected: no errors. `lib/l10n/generated/` updated.

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_th.arb
git commit -m "feat(families): l10n keys for families UI (EN + TH)"
```

---

## Task 7 — Router + Settings tile

**Files:**
- Modify: `lib/core/router/app_router.dart`
- Modify: `lib/features/settings/presentation/settings_screen.dart`

### 7a — Router

- [ ] **Step 1: Add route constant in `AppRoutes`**

In `app_router.dart`, inside `class AppRoutes`, add after `cloudBackup`:
```dart
  static const families       = '/settings/families';
```

- [ ] **Step 2: Add import for FamiliesScreen at top of `app_router.dart`**

```dart
import '../../features/families/presentation/families_screen.dart';
```

- [ ] **Step 3: Add GoRoute in the routes list**

The routes list already has entries like:
```dart
GoRoute(path: AppRoutes.manageDevices, builder: (_, __) => const ManageDevicesScreen()),
GoRoute(path: AppRoutes.cloudBackup, builder: (_, __) => const CloudBackupScreen()),
```

Add after `cloudBackup`:
```dart
GoRoute(path: AppRoutes.families, builder: (_, __) => const FamiliesScreen()),
```

- [ ] **Step 4: Verify**

```bash
flutter analyze lib/core/router/
```

Expected: no errors.

### 7b — Settings tile

- [ ] **Step 5: Add "Families" tile in the Security section of `settings_screen.dart`**

Find (around line 308):
```dart
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: Text(context.l10n.settingsCloudBackupTitle),
            subtitle: Text(context.l10n.settingsCloudBackupSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.cloudBackup),
          ),
          _SectionHeader(title: l10n.settingsSectionAbout),
```

Replace with:
```dart
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: Text(context.l10n.settingsCloudBackupTitle),
            subtitle: Text(context.l10n.settingsCloudBackupSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.cloudBackup),
          ),
          ListTile(
            leading: const Icon(Icons.group_outlined),
            title: Text(l10n.settingsFamiliesTitle),
            subtitle: Text(l10n.settingsFamiliesSubtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.families),
          ),
          _SectionHeader(title: l10n.settingsSectionAbout),
```

- [ ] **Step 6: Verify analysis + tests**

```bash
flutter analyze && flutter test
```

- [ ] **Step 7: Commit**

```bash
git add lib/core/router/app_router.dart lib/features/settings/presentation/settings_screen.dart
git commit -m "feat(families): add /settings/families route + Settings tile"
```

---

## Task 8 — `FamiliesScreen`

**Files:**
- Create: `lib/features/families/presentation/families_screen.dart`

This screen: lists all families (active one highlighted), allows switching, leaving, and adding a new family with premium gate.

"Add Another Family" calls the `bootstrap_family` Edge Function (same as welcome_screen) and uses `FamilyKeyService.generate()` to create K_family for the new family.

- [ ] **Step 1: Create `families_screen.dart`**

```dart
import 'dart:convert';

import 'package:dreambook/core/crypto/device_identity_service.dart';
import 'package:dreambook/core/crypto/family_key_service.dart';
import 'package:dreambook/core/families/family_entry.dart';
import 'package:dreambook/core/families/family_provider.dart';
import 'package:dreambook/core/families/family_repository.dart';
import 'package:dreambook/core/l10n/l10n_ext.dart';
import 'package:dreambook/core/providers/premium_provider.dart';
import 'package:dreambook/core/providers/shared_preferences_provider.dart';
import 'package:dreambook/core/router/app_router.dart';
import 'package:dreambook/core/sync/sync_lifecycle_controller.dart';
import 'package:dreambook/core/theme/design_tokens.dart';
import 'package:dreambook/features/baby/data/baby_repository.dart';
import 'package:dreambook/features/baby/data/current_baby_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _secureStorage = FlutterSecureStorage();

class FamiliesScreen extends ConsumerStatefulWidget {
  const FamiliesScreen({super.key});

  @override
  ConsumerState<FamiliesScreen> createState() => _FamiliesScreenState();
}

class _FamiliesScreenState extends ConsumerState<FamiliesScreen> {
  bool _adding = false;

  Future<void> _switchTo(String familyId) async {
    final notifier = ref.read(familyListProvider.notifier);
    await notifier.switchTo(familyId);

    // Clear stale baby selection — the new family may have different babies.
    await ref.read(currentBabyIdProvider.notifier).clear();

    // Rebuild sync worker for the new family.
    ref.invalidate(syncLifecycleControllerProvider);
    ref.read(syncLifecycleControllerProvider).syncNow().ignore();

    if (!mounted) return;
    context.go(AppRoutes.home);
  }

  Future<void> _leave(FamilyEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.familiesLeaveConfirmTitle),
        content: Text(ctx.l10n.familiesLeaveConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.familiesLeaveCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.l10n.familiesLeaveConfirmCta),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Delete K_family from secure storage.
    await FamilyKeyService(_secureStorage).clear(familyId: entry.id);

    // Remove from list (switches active if needed).
    await ref.read(familyListProvider.notifier).remove(entry.id);

    // Rebuild sync for the new active family (or no-op if list is empty).
    ref.invalidate(syncLifecycleControllerProvider);
  }

  Future<void> _addFamily() async {
    final families = ref.read(familyListProvider);
    final isPremium = await ref.read(isPremiumProvider.future);

    if (!ref.read(familyRepositoryProvider).canAddFamily(
          isPremium: isPremium,
          currentCount: families.length,
        )) {
      if (!mounted) return;
      context.push(AppRoutes.premium);
      return;
    }

    setState(() => _adding = true);
    try {
      final supa = Supabase.instance.client;
      if (supa.auth.currentSession == null) {
        await supa.auth.signInAnonymously();
      }

      final identity = await DeviceIdentityService(_secureStorage).getOrCreate();
      final resp = await supa.functions.invoke(
        'bootstrap_family',
        body: {'device_pub_key': base64Encode(identity.publicKeyBytes)},
      );
      if (resp.status != 201) throw Exception('bootstrap_family: ${resp.status}');

      final data = resp.data;
      if (data is! Map || data['family_id'] is! String) {
        throw Exception('bootstrap_family returned unexpected payload');
      }
      final familyId = data['family_id'] as String;

      await FamilyKeyService(_secureStorage).generate(
        familyId: familyId,
        keyVersion: 1,
      );

      final n = families.length + 1;
      await ref.read(familyListProvider.notifier).register(FamilyEntry(
            id: familyId,
            label: 'Family $n',
            createdAt: DateTime.now().toUtc(),
          ));

      // Switch active to the new family.
      await ref.read(familyListProvider.notifier).switchTo(familyId);
      await ref.read(sharedPreferencesProvider).setString('family.id', familyId);

      // Clear stale baby selection.
      await ref.read(currentBabyIdProvider.notifier).clear();

      // Rebuild sync worker for the new family.
      ref.invalidate(syncLifecycleControllerProvider);
      ref.read(syncLifecycleControllerProvider).syncNow().ignore();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.familiesCreated)),
      );
      context.go(AppRoutes.home);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.familiesCreatedError)),
      );
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final families = ref.watch(familyListProvider);
    final activeId = ref.read(familyRepositoryProvider).activeId();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.familiesTitle)),
      body: families.isEmpty
          ? Center(child: Text(l10n.familiesEmpty))
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              itemCount: families.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final entry = families[i];
                final isActive = entry.id == activeId;
                return ListTile(
                  leading: Icon(
                    Icons.group_outlined,
                    color: isActive
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  title: Text(entry.label),
                  subtitle: isActive ? Text(l10n.familiesActive) : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isActive)
                        TextButton(
                          onPressed: () => _switchTo(entry.id),
                          child: Text(l10n.familiesSwitch),
                        ),
                      if (families.length > 1)
                        TextButton(
                          onPressed: () => _leave(entry),
                          style: TextButton.styleFrom(
                            foregroundColor:
                                Theme.of(context).colorScheme.error,
                          ),
                          child: Text(l10n.familiesLeave),
                        ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: _adding
          ? const FloatingActionButton(
              onPressed: null,
              child: CircularProgressIndicator(),
            )
          : FloatingActionButton.extended(
              onPressed: _addFamily,
              icon: const Icon(Icons.add),
              label: Text(l10n.familiesAddAnother),
            ),
    );
  }
}
```

- [ ] **Step 2: Analyze**

```bash
flutter analyze lib/features/families/
```

Expected: no errors.

- [ ] **Step 3: Run all tests**

```bash
flutter test
```

Expected: all passing.

- [ ] **Step 4: Commit**

```bash
git add lib/features/families/presentation/families_screen.dart
git commit -m "feat(families): FamiliesScreen — list, switch, leave, add-another with premium gate"
```

---

## Task 9 — Home screen family banner

**Files:**
- Modify: `lib/features/home/presentation/home_screen.dart`

Show a small tappable banner below the AppBar when the user has more than one family, so they can quickly see which family is active and tap to switch.

- [ ] **Step 1: Add imports at top of `home_screen.dart`**

```dart
import 'package:dreambook/core/families/family_provider.dart';
```

- [ ] **Step 2: Add `_FamilyBanner` widget at the end of the file**

```dart
class _FamilyBanner extends ConsumerWidget {
  const _FamilyBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final families = ref.watch(familyListProvider);
    if (families.length <= 1) return const SizedBox.shrink();

    final repo = ref.read(familyRepositoryProvider);
    final activeId = repo.activeId();
    final active = families.firstWhere(
      (f) => f.id == activeId,
      orElse: () => families.first,
    );

    return GestureDetector(
      onTap: () => context.push(AppRoutes.families),
      child: Container(
        width: double.infinity,
        color: Theme.of(context).colorScheme.secondaryContainer,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xxs,
        ),
        child: Text(
          context.l10n.homeFamilyBanner(active.label),
          style: AppTypography.labelMedium(
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Insert `_FamilyBanner` as the first child of the Column in the body**

In `HomeScreen.build()`, find the inner `Column` inside the `SingleChildScrollView` (look for the existing `children: [` list that starts with `const SizedBox(height: AppSpacing.sm),`):

```dart
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.sm),
                  _TodayHeroCard(babyId: babyId),
```

Replace with:
```dart
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _FamilyBanner(),
                  const SizedBox(height: AppSpacing.sm),
                  _TodayHeroCard(babyId: babyId),
```

- [ ] **Step 4: Check that `AppRoutes.families` and `familyRepositoryProvider` are imported**

```bash
grep "families" lib/features/home/presentation/home_screen.dart | head -5
```

If `AppRoutes.families` isn't accessible (it's in `app_router.dart` which is already imported), no change needed. If `familyRepositoryProvider` import is missing, add it.

- [ ] **Step 5: Analyze + test**

```bash
flutter analyze lib/features/home/
flutter test
```

- [ ] **Step 6: Commit**

```bash
git add lib/features/home/presentation/home_screen.dart
git commit -m "feat(families): show family banner on Home when multiple families exist"
```

---

## Task 10 — Final verification

- [ ] **Step 1: Full analyze**

```bash
flutter analyze
```

Expected: 0 errors, 0 warnings.

- [ ] **Step 2: Full test suite**

```bash
flutter test
```

Expected: all tests pass. New count should be ≥ 317 (305 + 12 new family_repository tests).

- [ ] **Step 3: Verify l10n compiles**

```bash
flutter gen-l10n
```

Expected: no errors.

- [ ] **Step 4: Tag + final commit if needed**

```bash
git tag phase5-multi-family-complete
```

---

## Self-review checklist

### Spec coverage
| Spec requirement | Task |
|---|---|
| Family picker in home screen header, hidden at count=1 | Task 9 (`_FamilyBanner`) |
| "Add Another Family" CTA | Task 8 (`FamiliesScreen` FAB) |
| RC entitlement check at family-creation | Task 8 (`_addFamily` → `canAddFamily`) |
| Caregivers joining via invite free regardless of host tier | No gate in `claim_invite_screen.dart` — only new-family bootstrap is gated ✓ |
| Per-family BIP-39 phrase | Existing BIP-39 infra already namespaced by `family.id` — no new work needed for Phase 5 |
| "Leave family" button per family | Task 8 (`_leave`) |
| Secure storage namespacing already implemented | `FamilyKeyService` already uses `dreambook_family_key_v1::${familyId}` — no change ✓ |
| Beta to friend (1 family, 2 devices) | No code changes needed — already works with T1/T2/T3; Phase 5 just adds multi-family UI ✓ |

### Key invariants
- `family.id` in SharedPrefs is always the canonical active family ID — sync + queries read it directly.
- `FamilyRepository.switchTo()` updates only `family.id`; the list is unchanged.
- After switching, callers MUST: (1) clear `currentBabyIdProvider`, (2) `ref.invalidate(syncLifecycleControllerProvider)`.
- Premium gate is checked at `_addFamily()` time — caregivers joining via invite bypass the gate by design.
- `bootstrap_family` EF is idempotent for the same device pubkey — safe to call again for a second family because the device pubkey is unique per install, not per family (actually, the same pubkey will be registered in a NEW family row in `family_devices`).

### Potential issues
- **`_addFamily` shares the same device keypair** across families. This is intentional: the device identity (`DeviceIdentityService`) is per-device, not per-family. The `bootstrap_family` EF creates a new `families` row and links it to the same `auth.uid()`.
- **After leaving the last family**: `family.id` is set to `''`. The sync controller returns a `_NoOpSyncLifecycleController`. The user sees an empty home screen. They must either join a family or go through welcome again. This is acceptable for Phase 5 (premium feature, edge case).
- **`FamilyListNotifier.switchTo` copies the list** (`List.of(state)`) to force a Riverpod state rebuild even though the list contents haven't changed. This is correct because `state` is compared by identity in Riverpod 3.
