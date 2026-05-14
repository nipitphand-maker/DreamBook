import 'package:dreambook/core/models/vaccination.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VaccinationRecord', () {
    final base = VaccinationRecord(
      id: 'test-id',
      babyId: 'baby-id',
      vaccineName: 'DTaP',
      givenOn: DateTime(2025, 3, 15),
      createdAt: DateTime(2025, 3, 15, 10),
      updatedAt: DateTime(2025, 3, 15, 10),
    );

    group('toRow()', () {
      test('produces all expected keys', () {
        final row = base.toRow();

        expect(row.keys, containsAll([
          'id',
          'baby_id',
          'vaccine_name',
          'given_on',
          'clinic',
          'note',
          'logged_by',
          'created_at',
          'updated_at',
          'deleted_at',
          'version',
        ]));
      });

      test('serialises non-null fields to correct values', () {
        final row = base.toRow();

        expect(row['id'], 'test-id');
        expect(row['baby_id'], 'baby-id');
        expect(row['vaccine_name'], 'DTaP');
        expect(row['given_on'], DateTime(2025, 3, 15).toUtc().toIso8601String());
        expect(row['created_at'],
            DateTime(2025, 3, 15, 10).toUtc().toIso8601String());
        expect(row['updated_at'],
            DateTime(2025, 3, 15, 10).toUtc().toIso8601String());
        expect(row['version'], 1);
      });

      test('nullable fields are null when not set', () {
        final row = base.toRow();

        expect(row['clinic'], isNull);
        expect(row['note'], isNull);
        expect(row['logged_by'], isNull);
        expect(row['deleted_at'], isNull);
      });

      test('serialises optional string fields when set', () {
        final withOptionals = base.copyWith(
          clinic: 'City Pediatrics',
          note: 'mild fever after',
          loggedBy: 'nurse-1',
        );
        final row = withOptionals.toRow();

        expect(row['clinic'], 'City Pediatrics');
        expect(row['note'], 'mild fever after');
        expect(row['logged_by'], 'nurse-1');
      });

      test('serialises deletedAt as UTC ISO-8601 string when set', () {
        final deleted = DateTime.utc(2025, 6, 1, 9);
        final withDelete = base.copyWith(deletedAt: deleted);
        final row = withDelete.toRow();

        expect(row['deleted_at'], deleted.toIso8601String());
      });

      test('stores dates as UTC strings', () {
        // givenOn supplied as local time; toRow() must convert to UTC.
        final localTime = DateTime(2025, 3, 15, 12); // local noon
        final record = base.copyWith(givenOn: localTime);
        final row = record.toRow();

        expect(row['given_on'], localTime.toUtc().toIso8601String());
      });
    });

    group('fromRow()', () {
      test('round-trips all required fields', () {
        final row = base.toRow();
        final restored = VaccinationRecord.fromRow(row);

        expect(restored.id, base.id);
        expect(restored.babyId, base.babyId);
        expect(restored.vaccineName, base.vaccineName);
        expect(restored.version, base.version);
        expect(restored.clinic, isNull);
        expect(restored.note, isNull);
        expect(restored.loggedBy, isNull);
        expect(restored.deletedAt, isNull);
      });

      test('round-trips optional string fields', () {
        final full = VaccinationRecord(
          id: 'full-id',
          babyId: 'b2',
          vaccineName: 'MMR',
          givenOn: DateTime.utc(2025, 4, 20),
          clinic: 'General Hospital',
          note: 'no issues',
          loggedBy: 'dr-jones',
          createdAt: DateTime.utc(2025, 4, 20, 8),
          updatedAt: DateTime.utc(2025, 4, 20, 8),
          deletedAt: DateTime.utc(2025, 5, 1),
          version: 3,
        );

        final restored = VaccinationRecord.fromRow(full.toRow());

        expect(restored.id, full.id);
        expect(restored.babyId, full.babyId);
        expect(restored.vaccineName, full.vaccineName);
        expect(restored.givenOn, full.givenOn.toUtc());
        expect(restored.clinic, full.clinic);
        expect(restored.note, full.note);
        expect(restored.loggedBy, full.loggedBy);
        expect(restored.createdAt, full.createdAt.toUtc());
        expect(restored.updatedAt, full.updatedAt.toUtc());
        expect(restored.deletedAt, full.deletedAt!.toUtc());
        expect(restored.version, full.version);
      });

      test('handles null optional fields without throwing', () {
        final row = <String, Object?>{
          'id': 'x',
          'baby_id': 'b',
          'vaccine_name': 'Hep B',
          'given_on': '2025-01-01T00:00:00.000Z',
          'clinic': null,
          'note': null,
          'logged_by': null,
          'created_at': '2025-01-01T00:00:00.000Z',
          'updated_at': '2025-01-01T00:00:00.000Z',
          'deleted_at': null,
          'version': 1,
        };

        final record = VaccinationRecord.fromRow(row);

        expect(record.clinic, isNull);
        expect(record.note, isNull);
        expect(record.loggedBy, isNull);
        expect(record.deletedAt, isNull);
      });
    });

    group('defaults', () {
      test('deletedAt is null by default', () {
        expect(base.deletedAt, isNull);
      });

      test('version defaults to 1', () {
        expect(base.version, 1);
      });
    });

    group('copyWith()', () {
      test('returns a new instance with specified fields changed', () {
        final updated = base.copyWith(vaccineName: 'MMR', version: 2);

        expect(updated.vaccineName, 'MMR');
        expect(updated.version, 2);
        // Unchanged fields remain the same.
        expect(updated.id, base.id);
        expect(updated.babyId, base.babyId);
        expect(updated.givenOn, base.givenOn);
        expect(updated.createdAt, base.createdAt);
        expect(updated.updatedAt, base.updatedAt);
      });

      test('is not the same instance as the original', () {
        final copy = base.copyWith(vaccineName: 'Polio');
        expect(identical(copy, base), isFalse);
      });

      test('preserves all unspecified fields unchanged', () {
        final copy = base.copyWith();

        expect(copy.id, base.id);
        expect(copy.babyId, base.babyId);
        expect(copy.vaccineName, base.vaccineName);
        expect(copy.givenOn, base.givenOn);
        expect(copy.clinic, base.clinic);
        expect(copy.note, base.note);
        expect(copy.loggedBy, base.loggedBy);
        expect(copy.createdAt, base.createdAt);
        expect(copy.updatedAt, base.updatedAt);
        expect(copy.deletedAt, base.deletedAt);
        expect(copy.version, base.version);
      });

      test('can set deletedAt on a previously non-deleted record', () {
        final deletedAt = DateTime.utc(2025, 7, 1);
        final deleted = base.copyWith(deletedAt: deletedAt);

        expect(deleted.deletedAt, deletedAt);
        expect(base.deletedAt, isNull); // original unchanged
      });

      test('can update clinic and note independently', () {
        final withClinic = base.copyWith(clinic: 'Riverside');
        expect(withClinic.clinic, 'Riverside');
        expect(withClinic.note, isNull);

        final withNote = base.copyWith(note: 'mild reaction');
        expect(withNote.note, 'mild reaction');
        expect(withNote.clinic, isNull);
      });
    });
  });
}
