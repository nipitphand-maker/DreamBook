import 'package:flutter/foundation.dart';

enum SleepLocation { crib, stroller, car, other }

@immutable
class Sleep {
  const Sleep({
    required this.id,
    required this.babyId,
    required this.startedAt,
    this.endedAt,
    this.durationMin,
    this.location,
    this.note,
    this.loggedBy,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.version = 1,
  });

  final String id;
  final String babyId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final int? durationMin;
  final SleepLocation? location;
  final String? note;
  final String? loggedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;

  Sleep copyWith({
    String? id,
    String? babyId,
    DateTime? startedAt,
    DateTime? endedAt,
    int? durationMin,
    SleepLocation? location,
    String? note,
    String? loggedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    int? version,
  }) =>
      Sleep(
        id: id ?? this.id,
        babyId: babyId ?? this.babyId,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt ?? this.endedAt,
        durationMin: durationMin ?? this.durationMin,
        location: location ?? this.location,
        note: note ?? this.note,
        loggedBy: loggedBy ?? this.loggedBy,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt ?? this.deletedAt,
        version: version ?? this.version,
      );

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'baby_id': babyId,
        'started_at': startedAt.toUtc().toIso8601String(),
        'ended_at': endedAt?.toUtc().toIso8601String(),
        'duration_min': durationMin,
        'location': location == null ? null : _encodeLocation(location!),
        'note': note,
        'logged_by': loggedBy,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
        'version': version,
      };

  factory Sleep.fromRow(Map<String, Object?> r) => Sleep(
        id: r['id']! as String,
        babyId: r['baby_id']! as String,
        startedAt: DateTime.parse(r['started_at']! as String),
        endedAt: r['ended_at'] == null
            ? null
            : DateTime.parse(r['ended_at']! as String),
        durationMin: r['duration_min'] as int?,
        location: r['location'] == null
            ? null
            : _decodeLocation(r['location']! as String),
        note: r['note'] as String?,
        loggedBy: r['logged_by'] as String?,
        createdAt: DateTime.parse(r['created_at']! as String),
        updatedAt: DateTime.parse(r['updated_at']! as String),
        deletedAt: r['deleted_at'] == null
            ? null
            : DateTime.parse(r['deleted_at']! as String),
        version: r['version']! as int,
      );

  static String _encodeLocation(SleepLocation l) => switch (l) {
        SleepLocation.crib => 'crib',
        SleepLocation.stroller => 'stroller',
        SleepLocation.car => 'car',
        SleepLocation.other => 'other',
      };
  static SleepLocation _decodeLocation(String s) => switch (s) {
        'crib' => SleepLocation.crib,
        'stroller' => SleepLocation.stroller,
        'car' => SleepLocation.car,
        'other' => SleepLocation.other,
        _ => throw FormatException('Invalid SleepLocation: $s'),
      };
}
