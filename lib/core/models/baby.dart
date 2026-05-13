import 'package:flutter/foundation.dart';

enum BabySex { male, female, unspecified }

enum PreferredUnit { oz, ml }

@immutable
class Baby {
  const Baby({
    required this.id,
    required this.name,
    this.nickname,
    required this.dob,
    this.sex,
    this.photoPath,
    this.preferredUnit = PreferredUnit.oz,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.version = 1,
  });

  final String id;
  final String name;
  final String? nickname;
  final DateTime dob;
  final BabySex? sex;
  final String? photoPath;
  final PreferredUnit preferredUnit;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;

  Baby copyWith({
    String? id,
    String? name,
    String? nickname,
    DateTime? dob,
    BabySex? sex,
    String? photoPath,
    PreferredUnit? preferredUnit,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
    int? version,
  }) =>
      Baby(
        id: id ?? this.id,
        name: name ?? this.name,
        nickname: nickname ?? this.nickname,
        dob: dob ?? this.dob,
        sex: sex ?? this.sex,
        photoPath: photoPath ?? this.photoPath,
        preferredUnit: preferredUnit ?? this.preferredUnit,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt ?? this.deletedAt,
        version: version ?? this.version,
      );

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'name': name,
        'nickname': nickname,
        'dob': dob.toUtc().toIso8601String().substring(0, 10),
        'sex': sex == null ? null : _encodeSex(sex!),
        'photo_path': photoPath,
        'preferred_unit': _encodeUnit(preferredUnit),
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
        'deleted_at': deletedAt?.toUtc().toIso8601String(),
        'version': version,
      };

  factory Baby.fromRow(Map<String, Object?> r) => Baby(
        id: r['id']! as String,
        name: r['name']! as String,
        nickname: r['nickname'] as String?,
        dob: DateTime.parse(r['dob']! as String),
        sex: r['sex'] == null ? null : _decodeSex(r['sex']! as String),
        photoPath: r['photo_path'] as String?,
        preferredUnit: _decodeUnit(r['preferred_unit']! as String),
        createdAt: DateTime.parse(r['created_at']! as String),
        updatedAt: DateTime.parse(r['updated_at']! as String),
        deletedAt: r['deleted_at'] == null
            ? null
            : DateTime.parse(r['deleted_at']! as String),
        version: r['version']! as int,
      );

  static String _encodeSex(BabySex s) => switch (s) {
        BabySex.male => 'male',
        BabySex.female => 'female',
        BabySex.unspecified => 'unspecified',
      };
  static BabySex _decodeSex(String s) => switch (s) {
        'male' => BabySex.male,
        'female' => BabySex.female,
        'unspecified' => BabySex.unspecified,
        _ => throw FormatException('Invalid BabySex: $s'),
      };
  static String _encodeUnit(PreferredUnit u) => switch (u) {
        PreferredUnit.oz => 'oz',
        PreferredUnit.ml => 'ml',
      };
  static PreferredUnit _decodeUnit(String s) => switch (s) {
        'oz' => PreferredUnit.oz,
        'ml' => PreferredUnit.ml,
        _ => throw FormatException('Invalid PreferredUnit: $s'),
      };
}
