import 'package:flutter_test/flutter_test.dart';
import 'package:bellonotes/models/note.dart';
import 'package:bellonotes/models/folder.dart';
import 'package:bellonotes/providers/notes_provider.dart';
import 'package:bellonotes/providers/folders_provider.dart';
import 'package:bellonotes/services/database_service.dart';
import 'test_helpers.dart';

Note _note(String id, List<String> folders) => Note(
      id: id,
      content: 'Body $id',
      folderIds: folders,
      createdAt: DateTime(2024),
      modifiedAt: DateTime(2024),
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

  group('folder delete options', () {
    test('moveNotesToAllNotes detaches notes and keeps them active', () async {
      await DatabaseService.insertFolder(
          Folder(id: 'f1', name: 'F1', createdAt: DateTime(2024)));
      await DatabaseService.insertNote(_note('n1', ['f1']));
      await DatabaseService.deleteFolder('f1', moveNotesToAllNotes: true);

      final active = await DatabaseService.getAllNotes();
      expect(active.length, 1);
      expect(active.first.folderIds, isEmpty);
      expect((await DatabaseService.getTrashedNotes()), isEmpty);
    });

    test('!moveNotesToAllNotes sends notes to trash too', () async {
      await DatabaseService.insertFolder(
          Folder(id: 'f1', name: 'F1', createdAt: DateTime(2024)));
      await DatabaseService.insertNote(_note('n1', ['f1']));
      await DatabaseService.deleteFolder('f1', moveNotesToAllNotes: false);

      expect((await DatabaseService.getAllNotes()), isEmpty);
      final trashed = await DatabaseService.getTrashedNotes();
      expect(trashed.length, 1);
      // Membership preserved so the note returns with the folder.
      expect(trashed.first.folderIds, ['f1']);
    });

    test('restoring a folder also restores its trashed notes', () async {
      await DatabaseService.insertFolder(
          Folder(id: 'f1', name: 'F1', createdAt: DateTime(2024)));
      await DatabaseService.insertNote(_note('n1', ['f1']));
      await DatabaseService.deleteFolder('f1', moveNotesToAllNotes: false);
      await DatabaseService.restoreFolder('f1');

      final active = await DatabaseService.getAllNotes();
      expect(active.length, 1);
      expect((await DatabaseService.getTrashedFolders()), isEmpty);
    });
  });

  group('notes multi-select', () {
    test('deleteSelected moves all chosen notes to trash', () async {
      final p = NotesProvider();
      await p.loadNotes();
      final a = await p.createNote();
      final b = await p.createNote();
      await p.createNote();
      p.enterSelection(a.id);
      p.toggleSelected(b.id);
      expect(p.selectedCount, 2);
      await p.deleteSelected();
      await p.loadNotes();
      expect(p.notes.length, 1);
      expect(p.selectionMode, isFalse);
    });

    test('moveSelectedToFolder reassigns folders', () async {
      final fp = FoldersProvider();
      await fp.loadFolders();
      final f = await fp.createFolder('Work');
      final p = NotesProvider();
      await p.loadNotes();
      final a = await p.createNote();
      final b = await p.createNote();
      p.selectAll([a.id, b.id]);
      await p.moveSelectedToFolder([f.id]);
      await fp.refreshCounts();
      expect(fp.getNoteCountForFolder(f.id), 2);
    });

    test('restoreSelected brings trashed notes back', () async {
      final p = NotesProvider();
      await p.loadNotes();
      final a = await p.createNote();
      await p.deleteNote(a);
      await p.loadTrash();
      p.enterSelection(a.id);
      await p.restoreSelected();
      await p.loadNotes();
      expect(p.notes.length, 1);
    });
  });

  group('folders multi-select', () {
    test('deleteSelected removes multiple folders', () async {
      final fp = FoldersProvider();
      await fp.loadFolders();
      final a = await fp.createFolder('A');
      final b = await fp.createFolder('B');
      await fp.createFolder('C');
      fp.enterSelection(a.id);
      fp.toggleSelected(b.id);
      expect(fp.selectedCount, 2);
      await fp.deleteSelected();
      expect(fp.folders.length, 1);
      expect(fp.selectionMode, isFalse);
    });
  });
}
