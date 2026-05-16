import 'package:flutter/foundation.dart';

@immutable
class MilestoneAchievement {
  const MilestoneAchievement({
    required this.id,
    required this.babyId,
    required this.milestoneId,
    required this.achievedOn,
    this.note,
    required this.version,
    this.deletedAt,
    required this.updatedAt,
  });

  final String id;
  final String babyId;
  final String milestoneId;
  final DateTime achievedOn;
  final String? note;
  final int version;
  final DateTime? deletedAt;
  final DateTime updatedAt;

  MilestoneAchievement copyWith({
    String? id,
    String? babyId,
    String? milestoneId,
    DateTime? achievedOn,
    String? note,
    int? version,
    DateTime? deletedAt,
    DateTime? updatedAt,
  }) =>
      MilestoneAchievement(
        id: id ?? this.id,
        babyId: babyId ?? this.babyId,
        milestoneId: milestoneId ?? this.milestoneId,
        achievedOn: achievedOn ?? this.achievedOn,
        note: note ?? this.note,
        version: version ?? this.version,
        deletedAt: deletedAt ?? this.deletedAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'baby_id': babyId,
        'milestone_id': milestoneId,
        'achieved_on': achievedOn.toUtc().toIso8601String(),
        'note': note,
        'version': version,
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory MilestoneAchievement.fromRow(Map<String, Object?> r) =>
      MilestoneAchievement(
        id: r['id']! as String,
        babyId: r['baby_id']! as String,
        milestoneId: r['milestone_id']! as String,
        achievedOn: DateTime.parse(r['achieved_on']! as String),
        note: r['note'] as String?,
        version: r['version']! as int,
        deletedAt: r['deleted_at'] == null
            ? null
            : DateTime.parse(r['deleted_at']! as String),
        updatedAt: DateTime.parse(r['updated_at']! as String),
      );
}
