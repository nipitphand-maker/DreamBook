import 'package:flutter/foundation.dart';

enum DiaperType { pee, poop, mixed, dry }

@immutable
class Diaper {
  const Diaper({
    required this.id,
    required this.babyId,
    required this.type,
    this.color,
    this.consistency,
    required this.occurredAt,
    this.note,
    this.loggedBy,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.version = 1,
  });

  final String id;
  final String babyId;
  final DiaperType type;
  final String? color;
  final String? consistency;
  final DateTime occurredAt;
  final String? note;
  final String? loggedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;

  Diaper copyWith({
    String? id,
    String? babyId,
    DiaperType? type,
    bool clearColor = false,
    String? color,
    bool clearConsistency = false,
    String? consistency,
    DateTime? occurredAt,
    bool clearNote = false,
    String? note,
    bool clearLoggedBy = false,
    String? loggedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearDeletedAt = false,
    DateTime? deletedAt,
    int? version,
  }) =>
      Diaper(
        id: id ?? this.id,
        babyId: babyId ?? this.babyId,
        type: type ?? this.type,
        color: clearColor ? null : (color ?? this.color),
        consistency: clearConsistency ? null : (consistency ?? this.consistency),
        occurredAt: occurredAt ?? this.occurredAt,
        note: clearNote ? null : (note ?? this.note),
        loggedBy: clearLoggedBy ? null : (loggedBy ?? this.loggedBy),
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
        version: version ?? this.version,
      );

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'baby_id': babyId,
        'type': _encodeType(type),
        'color': color,
        'consistency': consistency,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'note': note,
        'logged_by': loggedBy,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
        'version': version,
      };

  factory Diaper.fromRow(Map<String, Object?> r) => Diaper(
        id: r['id']! as String,
        babyId: r['baby_id']! as String,
        type: _decodeType(r['type']! as String),
        color: r['color'] as String?,
        consistency: r['consistency'] as String?,
        occurredAt: DateTime.parse(r['occurred_at']! as String),
        note: r['note'] as String?,
        loggedBy: r['logged_by'] as String?,
        createdAt: DateTime.parse(r['created_at']! as String),
        updatedAt: DateTime.parse(r['updated_at']! as String),
        deletedAt: r['deleted_at'] == null
            ? null
            : DateTime.parse(r['deleted_at']! as String),
        version: r['version']! as int,
      );

  static String _encodeType(DiaperType t) => switch (t) {
        DiaperType.pee => 'pee',
        DiaperType.poop => 'poop',
        DiaperType.mixed => 'mixed',
        DiaperType.dry => 'dry',
      };
  static DiaperType _decodeType(String s) => switch (s) {
        'pee' => DiaperType.pee,
        'poop' => DiaperType.poop,
        'mixed' => DiaperType.mixed,
        'dry' => DiaperType.dry,
        _ => throw FormatException('Invalid DiaperType: $s'),
      };
}
