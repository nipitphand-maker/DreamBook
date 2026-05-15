class DailyNote {
  const DailyNote({
    required this.id,
    required this.babyId,
    required this.date,
    required this.body,
    required this.familyId,
    required this.keyVersion,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.version = 1,
  });

  final String id;
  final String babyId;

  /// Local calendar date in "YYYY-MM-DD" format.
  final String date;
  final String body;
  final String familyId;
  final int keyVersion;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;

  static DailyNote fromRow(Map<String, Object?> row) => DailyNote(
        id: row['id'] as String,
        babyId: row['baby_id'] as String,
        date: row['date'] as String,
        body: row['body'] as String,
        familyId: (row['family_id'] as String?) ?? '',
        keyVersion: (row['key_version'] as int?) ?? 1,
        createdAt: DateTime.parse(row['created_at'] as String),
        updatedAt: DateTime.parse(row['updated_at'] as String),
        deletedAt: row['deleted_at'] == null
            ? null
            : DateTime.parse(row['deleted_at'] as String),
        version: (row['version'] as int?) ?? 1,
      );

  Map<String, Object?> toRow() => {
        'id': id,
        'baby_id': babyId,
        'date': date,
        'body': body,
        'family_id': familyId,
        'key_version': keyVersion,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'deleted_at': deletedAt?.toIso8601String(),
        'version': version,
      };
}
