import 'package:flutter/foundation.dart';

enum StorageType { freezer, fridge, room }

enum BottleSource { pump, collector, split, leftover }

@immutable
class StashBottle {
  const StashBottle({
    required this.id,
    required this.babyId,
    this.pumpSessionId,
    required this.oz,
    required this.pumpedAt,
    this.frozenAt,
    required this.expiresAt,
    this.storage = StorageType.freezer,
    this.thawedAt,
    this.parentBottleId,
    this.source = BottleSource.pump,
    this.consumedAt,
    this.consumedFeedId,
    this.discardedAt,
    this.loggedBy,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.version = 1,
  });

  final String id;
  final String babyId;
  final String? pumpSessionId;
  final double oz;
  final DateTime pumpedAt;
  final DateTime? frozenAt;
  final DateTime expiresAt;
  final StorageType storage;
  final DateTime? thawedAt;
  final String? parentBottleId;
  final BottleSource source;
  final DateTime? consumedAt;
  final String? consumedFeedId;
  final DateTime? discardedAt;
  final String? loggedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;

  StashBottle copyWith({
    String? id,
    String? babyId,
    String? pumpSessionId,
    double? oz,
    DateTime? pumpedAt,
    DateTime? frozenAt,
    DateTime? expiresAt,
    StorageType? storage,
    DateTime? thawedAt,
    String? parentBottleId,
    BottleSource? source,
    DateTime? consumedAt,
    String? consumedFeedId,
    DateTime? discardedAt,
    String? loggedBy,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    int? version,
  }) =>
      StashBottle(
        id: id ?? this.id,
        babyId: babyId ?? this.babyId,
        pumpSessionId: pumpSessionId ?? this.pumpSessionId,
        oz: oz ?? this.oz,
        pumpedAt: pumpedAt ?? this.pumpedAt,
        frozenAt: frozenAt ?? this.frozenAt,
        expiresAt: expiresAt ?? this.expiresAt,
        storage: storage ?? this.storage,
        thawedAt: thawedAt ?? this.thawedAt,
        parentBottleId: parentBottleId ?? this.parentBottleId,
        source: source ?? this.source,
        consumedAt: consumedAt ?? this.consumedAt,
        consumedFeedId: consumedFeedId ?? this.consumedFeedId,
        discardedAt: discardedAt ?? this.discardedAt,
        loggedBy: loggedBy ?? this.loggedBy,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt ?? this.deletedAt,
        version: version ?? this.version,
      );

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'baby_id': babyId,
        'pump_session_id': pumpSessionId,
        'oz': oz,
        'pumped_at': pumpedAt.toUtc().toIso8601String(),
        'frozen_at': frozenAt?.toUtc().toIso8601String(),
        'expires_at': expiresAt.toUtc().toIso8601String(),
        'storage': _encodeStorage(storage),
        'thawed_at': thawedAt?.toUtc().toIso8601String(),
        'parent_bottle_id': parentBottleId,
        'source': _encodeSource(source),
        'consumed_at': consumedAt?.toUtc().toIso8601String(),
        'consumed_feed_id': consumedFeedId,
        'discarded_at': discardedAt?.toUtc().toIso8601String(),
        'logged_by': loggedBy,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
        'version': version,
      };

  factory StashBottle.fromRow(Map<String, Object?> r) => StashBottle(
        id: r['id']! as String,
        babyId: r['baby_id']! as String,
        pumpSessionId: r['pump_session_id'] as String?,
        oz: (r['oz']! as num).toDouble(),
        pumpedAt: DateTime.parse(r['pumped_at']! as String),
        frozenAt: r['frozen_at'] == null
            ? null
            : DateTime.parse(r['frozen_at']! as String),
        expiresAt: DateTime.parse(r['expires_at']! as String),
        storage: _decodeStorage(r['storage']! as String),
        thawedAt: r['thawed_at'] == null
            ? null
            : DateTime.parse(r['thawed_at']! as String),
        parentBottleId: r['parent_bottle_id'] as String?,
        source: _decodeSource(r['source']! as String),
        consumedAt: r['consumed_at'] == null
            ? null
            : DateTime.parse(r['consumed_at']! as String),
        consumedFeedId: r['consumed_feed_id'] as String?,
        discardedAt: r['discarded_at'] == null
            ? null
            : DateTime.parse(r['discarded_at']! as String),
        loggedBy: r['logged_by'] as String?,
        createdAt: DateTime.parse(r['created_at']! as String),
        updatedAt: DateTime.parse(r['updated_at']! as String),
        deletedAt: r['deleted_at'] == null
            ? null
            : DateTime.parse(r['deleted_at']! as String),
        version: r['version']! as int,
      );

  static String _encodeStorage(StorageType s) => switch (s) {
        StorageType.freezer => 'freezer',
        StorageType.fridge => 'fridge',
        StorageType.room => 'room',
      };
  static StorageType _decodeStorage(String s) => switch (s) {
        'freezer' => StorageType.freezer,
        'fridge' => StorageType.fridge,
        'room' => StorageType.room,
        _ => throw FormatException('Invalid StorageType: $s'),
      };
  static String _encodeSource(BottleSource s) => switch (s) {
        BottleSource.pump => 'pump',
        BottleSource.collector => 'collector',
        BottleSource.split => 'split',
        BottleSource.leftover => 'leftover',
      };
  static BottleSource _decodeSource(String s) => switch (s) {
        'pump' => BottleSource.pump,
        'collector' => BottleSource.collector,
        'split' => BottleSource.split,
        'leftover' => BottleSource.leftover,
        _ => throw FormatException('Invalid BottleSource: $s'),
      };
}
