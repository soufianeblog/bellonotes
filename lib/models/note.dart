// Immutable data model for a single note (title, rich-text content, folder
// membership, pin/color/trash flags, timestamps) plus SQLite row
// (de)serialization. Pure data — no UI or persistence logic here.
import 'dart:convert';

class Note {
  final String id;
  final String title;
  final String content;
  final List<String> folderIds;
  final bool isPinned;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final String? color;
  final String? highlightColor;
  final bool isDeleted;

  Note({
    required this.id,
    this.title = '',
    this.content = '',
    List<String>? folderIds,
    this.isPinned = false,
    required this.createdAt,
    required this.modifiedAt,
    this.color,
    this.highlightColor,
    this.isDeleted = false,
  }) : folderIds = folderIds ?? [];

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'content': content,
        'folder_id': folderIds.isNotEmpty ? jsonEncode(folderIds) : null,
        'is_pinned': isPinned ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'modified_at': modifiedAt.toIso8601String(),
        'color': color,
        'highlight_color': highlightColor,
        'is_deleted': isDeleted ? 1 : 0,
      };

  factory Note.fromMap(Map<String, dynamic> map) {
    List<String> parseFolderIds(dynamic val) {
      if (val == null) return [];
      if (val is String) {
        if (val.startsWith('[')) {
          try {
            final parsed = jsonDecode(val);
            if (parsed is List) {
              return parsed.map((e) => e.toString()).toList();
            }
          } catch (_) {}
        }
        return [val];
      }
      return [];
    }

    return Note(
      id: map['id'] as String,
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      folderIds: parseFolderIds(map['folder_id']),
      isPinned: (map['is_pinned'] as int?) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      modifiedAt: DateTime.parse(map['modified_at'] as String),
      color: map['color'] as String?,
      highlightColor: map['highlight_color'] as String?,
      isDeleted: (map['is_deleted'] as int?) == 1,
    );
  }

  Note copyWith({
    String? id,
    String? title,
    String? content,
    List<String>? folderIds,
    bool? isPinned,
    DateTime? createdAt,
    DateTime? modifiedAt,
    String? color,
    String? highlightColor,
    bool? isDeleted,
  }) =>
      Note(
        id: id ?? this.id,
        title: title ?? this.title,
        content: content ?? this.content,
        folderIds: folderIds ?? this.folderIds,
        isPinned: isPinned ?? this.isPinned,
        createdAt: createdAt ?? this.createdAt,
        modifiedAt: modifiedAt ?? this.modifiedAt,
        color: color ?? this.color,
        highlightColor: highlightColor ?? this.highlightColor,
        isDeleted: isDeleted ?? this.isDeleted,
      );

  String get folderId => folderIds.isNotEmpty ? folderIds.first : '';

  bool hasFolder(String id) => folderIds.contains(id);

  // Cached decoded plain text — decoding Delta JSON per list rebuild was a
  // major source of UI jank, so compute it lazily exactly once per instance.
  String? _plainTextCache;

  String get plainText {
    return _plainTextCache ??= _computePlainText();
  }

  String _computePlainText() {
    if (content.isEmpty) return '';
    try {
      final decoded = jsonDecode(content);
      if (decoded is List) {
        final sb = StringBuffer();
        for (final op in decoded) {
          if (op is Map && op.containsKey('insert')) {
            final insert = op['insert'];
            if (insert is String) sb.write(insert);
          }
        }
        final raw = sb.toString().trim();
        if (raw.isNotEmpty) return raw;
      }
    } catch (_) {}
    return content
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
        .replaceAll(RegExp(r"[#*>`~_|\-\\\[\]\{\}" "'" r'":,]+'), ' ')
        .trim();
  }

  /// A clean human-readable title: the stored title when sensible, otherwise
  /// the first line of the plain text. Never returns raw Delta/JSON.
  String get displayTitle {
    var t = title.trim();
    if (t.isNotEmpty && !t.startsWith('[') && !t.startsWith('{')) {
      return t.length > 120 ? t.substring(0, 120) : t;
    }
    t = plainText.split('\n').first.trim();
    return t.length > 120 ? t.substring(0, 120) : t;
  }

  /// Snippet shown beneath the title in the notes list (excludes first line).
  String get snippet {
    final lines = plainText.split('\n');
    final body = lines.length > 1 ? lines.sublist(1).join(' ') : '';
    final trimmed = body.trim();
    return trimmed.isEmpty ? '' : trimmed;
  }
}
