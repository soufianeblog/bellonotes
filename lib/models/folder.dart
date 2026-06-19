// Immutable data model for a folder (a named group of notes), plus SQLite
// row (de)serialization. Pure data — no UI or persistence logic here.
class Folder {
  final String id;
  final String name;
  final DateTime createdAt;
  final int sortOrder;
  final bool isDeleted;

  Folder({
    required this.id,
    required this.name,
    required this.createdAt,
    this.sortOrder = 0,
    this.isDeleted = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'created_at': createdAt.toIso8601String(),
        'sort_order': sortOrder,
        'is_deleted': isDeleted ? 1 : 0,
      };

  factory Folder.fromMap(Map<String, dynamic> map) => Folder(
        id: map['id'] as String,
        name: map['name'] as String,
        createdAt: DateTime.parse(map['created_at'] as String),
        sortOrder: map['sort_order'] as int? ?? 0,
        isDeleted: (map['is_deleted'] as int?) == 1,
      );

  Folder copyWith({
    String? id,
    String? name,
    DateTime? createdAt,
    int? sortOrder,
    bool? isDeleted,
  }) =>
      Folder(
        id: id ?? this.id,
        name: name ?? this.name,
        createdAt: createdAt ?? this.createdAt,
        sortOrder: sortOrder ?? this.sortOrder,
        isDeleted: isDeleted ?? this.isDeleted,
      );
}
