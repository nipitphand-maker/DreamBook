import 'package:flutter/foundation.dart';

@immutable
class TempReading {
  const TempReading({
    required this.id,
    required this.babyId,
    required this.takenAt,
    required this.celsius,
    required this.version,
    this.deletedAt,
    required this.updatedAt,
  });

  final String id;
  final String babyId;
  final DateTime takenAt;
  final double celsius;
  final int version;
  final DateTime? deletedAt;
  final DateTime updatedAt;

  double get fahrenheit => celsius * 9 / 5 + 32;

  static double toC(double f) => (f - 32) * 5 / 9;

  TempReading copyWith({
    String? id,
    String? babyId,
    DateTime? takenAt,
    double? celsius,
    int? version,
    bool clearDeletedAt = false,
    DateTime? deletedAt,
    DateTime? updatedAt,
  }) =>
      TempReading(
        id: id ?? this.id,
        babyId: babyId ?? this.babyId,
        takenAt: takenAt ?? this.takenAt,
        celsius: celsius ?? this.celsius,
        version: version ?? this.version,
        deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'baby_id': babyId,
        'taken_at': takenAt.toUtc().toIso8601String(),
        'celsius': celsius,
        'version': version,
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory TempReading.fromRow(Map<String, Object?> r) => TempReading(
        id: r['id']! as String,
        babyId: r['baby_id']! as String,
        takenAt: DateTime.parse(r['taken_at']! as String),
        celsius: (r['celsius']! as num).toDouble(),
        version: r['version']! as int,
        deletedAt: r['deleted_at'] == null
            ? null
            : DateTime.parse(r['deleted_at']! as String),
        updatedAt: DateTime.parse(r['updated_at']! as String),
      );
}
