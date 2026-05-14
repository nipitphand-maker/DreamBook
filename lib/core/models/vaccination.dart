import 'package:flutter/foundation.dart';

@immutable
class VaccinationRecord {
  const VaccinationRecord({
    required this.id,
    required this.babyId,
    required this.vaccineName,
    required this.givenOn,
    this.clinic,
    this.note,
    this.loggedBy,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.version = 1,
  });

  final String id;
  final String babyId;
  final String vaccineName;
  final DateTime givenOn;
  final String? clinic;
  final String? note;
  final String? loggedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;

  VaccinationRecord copyWith({
    String? id,
    String? babyId,
    String? vaccineName,
    DateTime? givenOn,
    String? clinic,
    String? note,
    String? loggedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    int? version,
  }) =>
      VaccinationRecord(
        id: id ?? this.id,
        babyId: babyId ?? this.babyId,
        vaccineName: vaccineName ?? this.vaccineName,
        givenOn: givenOn ?? this.givenOn,
        clinic: clinic ?? this.clinic,
        note: note ?? this.note,
        loggedBy: loggedBy ?? this.loggedBy,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt ?? this.deletedAt,
        version: version ?? this.version,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'baby_id': babyId,
        'vaccine_name': vaccineName,
        'given_on': givenOn.toUtc().toIso8601String(),
        'clinic': clinic,
        'note': note,
        'logged_by': loggedBy,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
        'version': version,
      };

  factory VaccinationRecord.fromRow(Map<String, Object?> r) => VaccinationRecord(
        id: r['id']! as String,
        babyId: r['baby_id']! as String,
        vaccineName: r['vaccine_name']! as String,
        givenOn: DateTime.parse(r['given_on']! as String),
        clinic: r['clinic'] as String?,
        note: r['note'] as String?,
        loggedBy: r['logged_by'] as String?,
        createdAt: DateTime.parse(r['created_at']! as String),
        updatedAt: DateTime.parse(r['updated_at']! as String),
        deletedAt: r['deleted_at'] == null
            ? null
            : DateTime.parse(r['deleted_at']! as String),
        version: r['version']! as int,
      );
}
