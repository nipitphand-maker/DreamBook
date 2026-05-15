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
      final entry = FamilyEntry(id: 'f1', label: "Emma's Family", createdAt: DateTime(2026));
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
