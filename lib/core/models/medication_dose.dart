import 'package:flutter/foundation.dart';

@immutable
class MedicationDose {
  const MedicationDose({
    required this.id,
    required this.babyId,
    required this.drugName,
    required this.doseAmount,
    required this.doseUnit,
    required this.givenAt,
    this.nextDoseAt,
    this.note,
    required this.version,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String babyId;
  final String drugName;
  final double doseAmount;

  /// 'mg' | 'ml' | 'tablet'
  final String doseUnit;
  final DateTime givenAt;
  final DateTime? nextDoseAt;
  final String? note;
  final int version;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  MedicationDose copyWith({
    String? id,
    String? babyId,
    String? drugName,
    double? doseAmount,
    String? doseUnit,
    DateTime? givenAt,
    DateTime? nextDoseAt,
    String? note,
    int? version,
    DateTime? deletedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      MedicationDose(
        id: id ?? this.id,
        babyId: babyId ?? this.babyId,
        drugName: drugName ?? this.drugName,
        doseAmount: doseAmount ?? this.doseAmount,
        doseUnit: doseUnit ?? this.doseUnit,
        givenAt: givenAt ?? this.givenAt,
        nextDoseAt: nextDoseAt ?? this.nextDoseAt,
        note: note ?? this.note,
        version: version ?? this.version,
        deletedAt: deletedAt ?? this.deletedAt,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'baby_id': babyId,
        'drug_name': drugName,
        'dose_amount': doseAmount,
        'dose_unit': doseUnit,
        'given_at': givenAt.toUtc().toIso8601String(),
        'next_dose_at': nextDoseAt?.toUtc().toIso8601String(),
        'note': note,
        'version': version,
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory MedicationDose.fromRow(Map<String, Object?> r) => MedicationDose(
        id: r['id']! as String,
        babyId: r['baby_id']! as String,
        drugName: r['drug_name']! as String,
        doseAmount: (r['dose_amount']! as num).toDouble(),
        doseUnit: r['dose_unit']! as String,
        givenAt: DateTime.parse(r['given_at']! as String),
        nextDoseAt: r['next_dose_at'] == null
            ? null
            : DateTime.parse(r['next_dose_at']! as String),
        note: r['note'] as String?,
        version: r['version']! as int,
        deletedAt: r['deleted_at'] == null
            ? null
            : DateTime.parse(r['deleted_at']! as String),
        createdAt: DateTime.parse(
          (r['created_at'] as String?)?.isNotEmpty == true
              ? r['created_at']! as String
              : r['updated_at']! as String,
        ),
        updatedAt: DateTime.parse(r['updated_at']! as String),
      );
}
