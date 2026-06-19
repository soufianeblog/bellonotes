import 'package:flutter_test/flutter_test.dart';
import 'package:bellonotes/providers/notes_provider.dart';
import 'package:bellonotes/providers/folders_provider.dart';
import 'package:bellonotes/services/database_service.dart';
import 'test_helpers.dart';

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

  group('NotesProvider', () {
    test('create note selects it and bumps count', () async {
      final p = NotesProvider();
      await p.loadNotes();
      final note = await p.createNote();
      expect(p.selectedNote?.id, note.id);
      expect(p.noteCount, 1);
    });

    test('updating content derives the title from first line', () async {
      final p = NotesProvider();
      await p.loadNotes();
      final note = await p.createNote();
      await p.updateNoteContent(note, 'Hello there\nsecond line');
      expect(p.selectedNote?.title, 'Hello there');
    });

    test('delete moves to trash and restore brings back', () async {
      final p = NotesProvider();
      await p.loadNotes();
      final note = await p.createNote();
      await p.deleteNote(note);
      expect(p.notes.where((n) => n.id == note.id), isEmpty);
      expect(p.trashedNoteCount, 1);
      await p.loadTrash();
      await p.restoreNote(note.id);
      await p.loadNotes();
      expect(p.notes.where((n) => n.id == note.id).length, 1);
    });

    test('sort by title A-Z orders notes', () async {
      final p = NotesProvider();
      await p.loadNotes();
      final a = await p.createNote();
      await p.updateNoteContent(a, 'Zebra');
      final b = await p.createNote();
      await p.updateNoteContent(b, 'Apple');
      await p.loadNotes();
      p.sortNotes(NotesSortOrder.titleAz);
      expect(p.notes.first.title, 'Apple');
      p.sortNotes(NotesSortOrder.titleZa);
      expect(p.notes.first.title, 'Zebra');
    });

    test('pinned notes sort ahead of unpinned', () async {
      final p = NotesProvider();
      await p.loadNotes();
      final a = await p.createNote();
      await p.updateNoteContent(a, 'AAA');
      final b = await p.createNote();
      await p.updateNoteContent(b, 'BBB');
      await p.loadNotes();
      await p.togglePin(b);
      expect(p.notes.first.id, b.id);
      expect(p.notes.first.isPinned, isTrue);
    });

    test('search narrows the visible notes', () async {
      final p = NotesProvider();
      await p.loadNotes();
      final a = await p.createNote();
      await p.updateNoteContent(a, 'groceries milk');
      final b = await p.createNote();
      await p.updateNoteContent(b, 'meeting notes');
      await p.searchNotes('groceries');
      expect(p.notes.length, 1);
      expect(p.notes.first.id, a.id);
    });
  });

  group('FoldersProvider', () {
    test('create, rename and delete folder', () async {
      final fp = FoldersProvider();
      await fp.loadFolders();
      final f = await fp.createFolder('Work');
      expect(fp.folders.length, 1);
      await fp.renameFolder(f, 'Personal');
      expect(fp.folders.first.name, 'Personal');
      await fp.deleteFolder(f);
      expect(fp.folders, isEmpty);
    });

    test('note counts update via refreshCounts', () async {
      final fp = FoldersProvider();
      await fp.loadFolders();
      final f = await fp.createFolder('Work');
      final np = NotesProvider();
      await np.loadNotes();
      final note = await np.createNote(folderId: f.id);
      await np.moveNoteToFolder(note, [f.id]);
      await fp.refreshCounts();
      expect(fp.getNoteCountForFolder(f.id), 1);
    });
  });
}
