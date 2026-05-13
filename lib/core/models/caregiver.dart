import 'package:flutter/foundation.dart';

enum CaregiverRole { readOnly, editor, admin }

@immutable
class Caregiver {
  const Caregiver({
    required this.id,
    required this.displayName,
    required this.deviceId,
    this.role = CaregiverRole.editor,
    required this.joinedAt,
    this.revokedAt,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.version = 1,
  });

  final String id;
  final String displayName;
  final String deviceId;
  final CaregiverRole role;
  final DateTime joinedAt;
  final DateTime? revokedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;

  Caregiver copyWith({
    String? id,
    String? displayName,
    String? deviceId,
    CaregiverRole? role,
    DateTime? joinedAt,
    DateTime? revokedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    int? version,
  }) =>
      Caregiver(
        id: id ?? this.id,
        displayName: displayName ?? this.displayName,
        deviceId: deviceId ?? this.deviceId,
        role: role ?? this.role,
        joinedAt: joinedAt ?? this.joinedAt,
        revokedAt: revokedAt ?? this.revokedAt,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt ?? this.deletedAt,
        version: version ?? this.version,
      );

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'display_name': displayName,
        'device_id': deviceId,
        'role': _encodeRole(role),
        'joined_at': joinedAt.toUtc().toIso8601String(),
        'revoked_at': revokedAt?.toUtc().toIso8601String(),
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
        'version': version,
      };

  factory Caregiver.fromRow(Map<String, Object?> r) => Caregiver(
        id: r['id']! as String,
        displayName: r['display_name']! as String,
        deviceId: r['device_id']! as String,
        role: _decodeRole(r['role']! as String),
        joinedAt: DateTime.parse(r['joined_at']! as String),
        revokedAt: r['revoked_at'] == null
            ? null
            : DateTime.parse(r['revoked_at']! as String),
        createdAt: DateTime.parse(r['created_at']! as String),
        updatedAt: DateTime.parse(r['updated_at']! as String),
        deletedAt: r['deleted_at'] == null
            ? null
            : DateTime.parse(r['deleted_at']! as String),
        version: r['version']! as int,
      );

  static String _encodeRole(CaregiverRole r) => switch (r) {
        CaregiverRole.readOnly => 'read_only',
        CaregiverRole.editor => 'editor',
        CaregiverRole.admin => 'admin',
      };
  static CaregiverRole _decodeRole(String s) => switch (s) {
        'read_only' => CaregiverRole.readOnly,
        'editor' => CaregiverRole.editor,
        'admin' => CaregiverRole.admin,
        _ => throw FormatException('Invalid CaregiverRole: $s'),
      };
}
