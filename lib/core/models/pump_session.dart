import 'package:flutter/foundation.dart';

@immutable
class PumpSession {
  const PumpSession({
    required this.id,
    required this.babyId,
    this.leftOz = 0,
    this.rightOz = 0,
    this.durationMin,
    this.pausedDurationMin = 0,
    required this.startedAt,
    this.endedAt,
    this.note,
    this.loggedBy,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.version = 1,
  });

  final String id;
  final String babyId;
  final double leftOz;
  final double rightOz;
  final int? durationMin;
  final int pausedDurationMin;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? note;
  final String? loggedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;

  double get totalOz => leftOz + rightOz;

  PumpSession copyWith({
    String? id,
    String? babyId,
    double? leftOz,
    double? rightOz,
    int? durationMin,
    int? pausedDurationMin,
    DateTime? startedAt,
    DateTime? endedAt,
    String? note,
    String? loggedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    int? version,
  }) =>
      PumpSession(
        id: id ?? this.id,
        babyId: babyId ?? this.babyId,
        leftOz: leftOz ?? this.leftOz,
        rightOz: rightOz ?? this.rightOz,
        durationMin: durationMin ?? this.durationMin,
        pausedDurationMin: pausedDurationMin ?? this.pausedDurationMin,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt ?? this.endedAt,
        note: note ?? this.note,
        loggedBy: loggedBy ?? this.loggedBy,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt ?? this.deletedAt,
        version: version ?? this.version,
      );

  /// Note: `total_oz` is a VIRTUAL column in SQLite — never written.
  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'baby_id': babyId,
        'left_oz': leftOz,
        'right_oz': rightOz,
        'duration_min': durationMin,
        'paused_duration_min': pausedDurationMin,
        'started_at': startedAt.toUtc().toIso8601String(),
        'ended_at': endedAt?.toUtc().toIso8601String(),
        'note': note,
        'logged_by': loggedBy,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
        'version': version,
      };

  factory PumpSession.fromRow(Map<String, Object?> r) => PumpSession(
        id: r['id']! as String,
        babyId: r['baby_id']! as String,
        leftOz: (r['left_oz']! as num).toDouble(),
        rightOz: (r['right_oz']! as num).toDouble(),
        durationMin: r['duration_min'] as int?,
        pausedDurationMin: r['paused_duration_min'] as int? ?? 0,
        startedAt: DateTime.parse(r['started_at']! as String),
        endedAt: r['ended_at'] == null
            ? null
            : DateTime.parse(r['ended_at']! as String),
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
