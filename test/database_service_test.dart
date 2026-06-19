import 'package:flutter_test/flutter_test.dart';
import 'package:bellonotes/models/note.dart';
import 'package:bellonotes/models/folder.dart';
import 'package:bellonotes/services/database_service.dart';
import 'test_helpers.dart';

Note _note(String id, {List<String>? folders, bool deleted = false}) => Note(
      id: id,
      title: 'Title $id',
      content: 'Body $id',
      folderIds: folders,
      isDeleted: deleted,
      createdAt: DateTime(2024, 1, 1),
      modifiedAt: DateTime(2024, 1, 1),
    );

void main() {
  setUp(() async {
    await initTestEnvironment();
    await deleteDbFile();
    await DatabaseService.resetForTests();
  });

  tearDown(() async {
    await DatabaseService.resetForTests();
    await cleanupTestEnvironment();
  });

  test('insert + query notes', () async {
    await DatabaseService.insertNote(_note('a'));
    await DatabaseService.insertNote(_note('b'));
    final all = await DatabaseService.getAllNotes();
    expect(all.length, 2);
  });

  test('soft delete moves note to trash', () async {
    await DatabaseService.insertNote(_note('a'));
    await DatabaseService.deleteNote('a');
    expect((await DatabaseService.getAllNotes()).length, 0);
    expect((await DatabaseService.getTrashedNotes()).length, 1);
    expect(await DatabaseService.getTrashedNoteCount(), 1);
  });

  test('restore note brings it back', () async {
    await DatabaseService.insertNote(_note('a'));
    await DatabaseService.deleteNote('a');
    await DatabaseService.restoreNote('a');
    expect((await DatabaseService.getAllNotes()).length, 1);
    expect((await DatabaseService.getTrashedNotes()).length, 0);
  });

  test('folder note counts handle multi-folder notes', () async {
    await DatabaseService.insertFolder(Folder(
        id: 'f1', name: 'F1', createdAt: DateTime(2024)));
    await DatabaseService.insertFolder(Folder(
        id: 'f2', name: 'F2', createdAt: DateTime(2024)));
    await DatabaseService.insertNote(_note('a', folders: ['f1', 'f2']));
    await DatabaseService.insertNote(_note('b', folders: ['f1']));
    final counts = await DatabaseService.getNoteCountsPerFolder();
    expect(counts['f1'], 2);
    expect(counts['f2'], 1);
  });

  test('getNotes filters by folder including multi-folder membership',
      () async {
    await DatabaseService.insertNote(_note('a', folders: ['f1', 'f2']));
    await DatabaseService.insertNote(_note('b', folders: ['f2']));
    final f1 = await DatabaseService.getNotes(folderId: 'f1');
    expect(f1.map((n) => n.id), contains('a'));
    expect(f1.map((n) => n.id), isNot(contains('b')));
  });

  test('search matches title and content', () async {
    await DatabaseService.insertNote(_note('a'));
    final res = await DatabaseService.getAllNotes(search: 'Body a');
    expect(res.length, 1);
    final none = await DatabaseService.getAllNotes(search: 'zzzz');
    expect(none.length, 0);
  });

  test('deleting a folder detaches it from notes', () async {
    await DatabaseService.insertFolder(Folder(
        id: 'f1', name: 'F1', createdAt: DateTime(2024)));
    await DatabaseService.insertNote(_note('a', folders: ['f1']));
    await DatabaseService.deleteFolder('f1');
    final note = (await DatabaseService.getAllNotes()).first;
    expect(note.folderIds, isEmpty);
  });

  test('importData replaces rows with matching ids', () async {
    await DatabaseService.insertNote(_note('a'));
    final updated = _note('a').copyWith(title: 'Updated');
    await DatabaseService.importData([], [updated]);
    final all = await DatabaseService.getAllNotes();
    expect(all.length, 1);
    expect(all.first.title, 'Updated');
  });
}
