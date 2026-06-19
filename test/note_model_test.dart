import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:bellonotes/models/note.dart';

Note _note({String content = '', String title = ''}) => Note(
      id: 'n1',
      title: title,
      content: content,
      createdAt: DateTime(2024, 1, 1),
      modifiedAt: DateTime(2024, 1, 2),
    );

void main() {
  group('Note.plainText', () {
    test('decodes a Quill delta to readable text', () {
      final delta = jsonEncode([
        {'insert': 'Hello world\n'}
      ]);
      expect(_note(content: delta).plainText, 'Hello world');
    });

    test('strips markdown when content is not delta', () {
      final n = _note(content: '# Title\n**bold** text');
      expect(n.plainText.contains('#'), isFalse);
      expect(n.plainText.contains('Title'), isTrue);
    });

    test('empty content yields empty string', () {
      expect(_note().plainText, '');
    });

    test('result is cached (same instance returns identical value)', () {
      final n = _note(content: jsonEncode([
        {'insert': 'cache me\n'}
      ]));
      final a = n.plainText;
      final b = n.plainText;
      expect(identical(a, b), isTrue);
    });
  });

  group('Note.displayTitle', () {
    test('uses first line of delta content', () {
      final delta = jsonEncode([
        {'insert': 'My Heading\nbody line\n'}
      ]);
      expect(_note(content: delta).displayTitle, 'My Heading');
    });

    test('never returns raw JSON when title looks like delta', () {
      final delta = jsonEncode([
        {'insert': 'Real Title\nmore\n'}
      ]);
      final n = _note(content: delta, title: '[{"insert":"x"}]');
      expect(n.displayTitle, 'Real Title');
      expect(n.displayTitle.startsWith('['), isFalse);
    });

    test('falls back gracefully for empty note', () {
      expect(_note().displayTitle, '');
    });
  });

  group('Note.snippet', () {
    test('excludes the first (title) line', () {
      final delta = jsonEncode([
        {'insert': 'Title line\nThe body snippet here\n'}
      ]);
      expect(_note(content: delta).snippet, 'The body snippet here');
    });

    test('is empty when there is only a title line', () {
      final delta = jsonEncode([
        {'insert': 'Only title\n'}
      ]);
      expect(_note(content: delta).snippet, '');
    });
  });

  group('Note serialization', () {
    test('folderIds round-trip through map', () {
      final n = Note(
        id: 'x',
        folderIds: ['a', 'b'],
        createdAt: DateTime(2024),
        modifiedAt: DateTime(2024),
      );
      final restored = Note.fromMap(n.toMap());
      expect(restored.folderIds, ['a', 'b']);
    });

    test('legacy single string folder_id parses to a list', () {
      final restored = Note.fromMap({
        'id': 'x',
        'title': '',
        'content': '',
        'folder_id': 'legacy-folder',
        'is_pinned': 0,
        'created_at': DateTime(2024).toIso8601String(),
        'modified_at': DateTime(2024).toIso8601String(),
        'is_deleted': 0,
      });
      expect(restored.folderIds, ['legacy-folder']);
    });

    test('null folder_id yields empty list', () {
      final restored = Note.fromMap({
        'id': 'x',
        'title': '',
        'content': '',
        'folder_id': null,
        'is_pinned': 0,
        'created_at': DateTime(2024).toIso8601String(),
        'modified_at': DateTime(2024).toIso8601String(),
        'is_deleted': 0,
      });
      expect(restored.folderIds, isEmpty);
    });
  });
}
