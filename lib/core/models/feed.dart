import 'package:flutter/foundation.dart';

enum FeedType { breast, bottle }

enum FeedSide { left, right, both }

enum FeedSource { breastmilk, formula }

@immutable
class Feed {
  const Feed({
    required this.id,
    required this.babyId,
    required this.type,
    this.side,
    this.oz,
    this.source,
    this.fromStashBottleId,
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
  final FeedType type;
  final FeedSide? side;
  final double? oz;
  final FeedSource? source;
  final String? fromStashBottleId;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? note;
  final String? loggedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;

  Feed copyWith({
    String? id,
    String? babyId,
    FeedType? type,
    FeedSide? side,
    double? oz,
    FeedSource? source,
    String? fromStashBottleId,
    DateTime? startedAt,
    DateTime? endedAt,
    String? note,
    String? loggedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    int? version,
  }) =>
      Feed(
        id: id ?? this.id,
        babyId: babyId ?? this.babyId,
        type: type ?? this.type,
        side: side ?? this.side,
        oz: oz ?? this.oz,
        source: source ?? this.source,
        fromStashBottleId: fromStashBottleId ?? this.fromStashBottleId,
        startedAt: startedAt ?? this.startedAt,
        endedAt: endedAt ?? this.endedAt,
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
        'type': _encodeType(type),
        'side': side == null ? null : _encodeSide(side!),
        'oz': oz,
        'source': source == null ? null : _encodeSource(source!),
        'from_stash_bottle_id': fromStashBottleId,
        'started_at': startedAt.toUtc().toIso8601String(),
        'ended_at': endedAt?.toUtc().toIso8601String(),
        'note': note,
        'logged_by': loggedBy,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
        'version': version,
      };

  factory Feed.fromRow(Map<String, Object?> r) => Feed(
        id: r['id']! as String,
        babyId: r['baby_id']! as String,
        type: _decodeType(r['type']! as String),
        side: r['side'] == null ? null : _decodeSide(r['side']! as String),
        oz: (r['oz'] as num?)?.toDouble(),
        source: r['source'] == null
            ? null
            : _decodeSource(r['source']! as String),
        fromStashBottleId: r['from_stash_bottle_id'] as String?,
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

  static String _encodeType(FeedType t) => switch (t) {
        FeedType.breast => 'breast',
        FeedType.bottle => 'bottle',
      };
  static FeedType _decodeType(String s) => switch (s) {
        'breast' => FeedType.breast,
        'bottle' => FeedType.bottle,
        _ => throw FormatException('Invalid FeedType: $s'),
      };
  static String _encodeSide(FeedSide s) => switch (s) {
        FeedSide.left => 'left',
        FeedSide.right => 'right',
        FeedSide.both => 'both',
      };
  static FeedSide _decodeSide(String s) => switch (s) {
        'left' => FeedSide.left,
        'right' => FeedSide.right,
        'both' => FeedSide.both,
        _ => throw FormatException('Invalid FeedSide: $s'),
      };
  static String _encodeSource(FeedSource s) => switch (s) {
        FeedSource.breastmilk => 'breastmilk',
        FeedSource.formula => 'formula',
      };
  static FeedSource _decodeSource(String s) => switch (s) {
        'breastmilk' => FeedSource.breastmilk,
        'formula' => FeedSource.formula,
        _ => throw FormatException('Invalid FeedSource: $s'),
      };
}
