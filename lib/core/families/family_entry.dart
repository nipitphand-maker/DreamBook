import 'dart:convert';

class FamilyEntry {
  const FamilyEntry({
    required this.id,
    required this.label,
    required this.createdAt,
  });

  final String id;
  final String label;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'createdAt': createdAt.toIso8601String(),
      };

  factory FamilyEntry.fromJson(Map<String, dynamic> j) => FamilyEntry(
        id: j['id'] as String,
        label: j['label'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );

  static List<FamilyEntry> listFromJson(String raw) {
    final list = jsonDecode(raw) as List;
    return list.map((e) => FamilyEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  static String listToJson(List<FamilyEntry> entries) =>
      jsonEncode(entries.map((e) => e.toJson()).toList());
}
