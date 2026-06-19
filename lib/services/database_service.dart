// Local SQLite persistence layer for notes and folders. Owns the schema,
// migrations, and all CRUD queries. Uses the FFI SQLite backend on desktop and
// the default sqflite backend on mobile. All state-holders go through here.
import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/note.dart';
import '../models/folder.dart';

class DatabaseService {
  static Database? _database;
  static bool _ffiInitialized = false;
  static const int _dbVersion = 2;

  static Future<void> _ensureFfi() async {
    if (_ffiInitialized) return;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // Load the bundled native SQLite (FFI) library. We deliberately do NOT
      // assign the global `databaseFactory`: the desktop path in
      // [_initDatabase] opens via `databaseFactoryFfi.openDatabase(...)`
      // directly, so overriding the global factory is unnecessary — and doing
      // so makes sqflite print a noisy "changing sqflite default factory"
      // warning on every launch.
      sqfliteFfiInit();
    }
    _ffiInitialized = true;
  }

  static Future<Database> get database async {
    if (_database != null) return _database!;
    await _ensureFfi();
    _database = await _initDatabase();
    return _database!;
  }

  /// Closes and clears the cached database. Used by tests for isolation.
  static Future<void> resetForTests() async {
    await _database?.close();
    _database = null;
  }

  static Future<Database> _initDatabase() async {
    final dir = await getApplicationDocumentsDirectory();

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final dbPath = p.join(dir.path, 'bellonotes.db');
      return await databaseFactoryFfi.openDatabase(
        dbPath,
        options: OpenDatabaseOptions(
          version: _dbVersion,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        ),
      );
    }

    final dbPath = p.join(dir.path, 'bellonotes.db');
    return await openDatabase(
      dbPath,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE folders (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL DEFAULT '',
        content TEXT NOT NULL DEFAULT '',
        folder_id TEXT,
        is_pinned INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        modified_at TEXT NOT NULL,
        color TEXT,
        highlight_color TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE SET NULL
      )
    ''');

    await db.execute('CREATE INDEX idx_notes_folder ON notes(folder_id)');
    await db.execute('CREATE INDEX idx_notes_modified ON notes(modified_at)');
    await db.execute('CREATE INDEX idx_notes_pinned ON notes(is_pinned)');
    await db.execute('CREATE INDEX idx_notes_deleted ON notes(is_deleted)');
    await db.execute('CREATE INDEX idx_folders_deleted ON folders(is_deleted)');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          'ALTER TABLE notes ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0');
      await db.execute(
          'ALTER TABLE folders ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_notes_deleted ON notes(is_deleted)');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_folders_deleted ON folders(is_deleted)');
    }
  }

  static Future<List<Folder>> getFolders() async {
    final db = await database;
    final maps = await db.query('folders',
        where: 'is_deleted = 0', orderBy: 'sort_order ASC, name ASC');
    return maps.map((m) => Folder.fromMap(m)).toList();
  }

  static Future<void> insertFolder(Folder folder) async {
    final db = await database;
    await db.insert('folders', folder.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> updateFolder(Folder folder) async {
    final db = await database;
    await db.update('folders', folder.toMap(),
        where: 'id = ?', whereArgs: [folder.id]);
  }

  static Future<void> _removeFolderFromNotes(
      Database db, String folderId) async {
    final allNotes = await db.query('notes', where: 'is_deleted = 0');
    for (final n in allNotes) {
      final note = Note.fromMap(n);
      if (note.hasFolder(folderId)) {
        final updated = note.folderIds.where((id) => id != folderId).toList();
        await db.update('notes',
            {'folder_id': updated.isNotEmpty ? json.encode(updated) : null},
            where: 'id = ?',
            whereArgs: [note.id]);
      }
    }
  }

  /// Soft-deletes a folder (moves it to Trash). When [moveNotesToAllNotes] is
  /// true the folder's notes are detached and remain in All Notes; otherwise
  /// the notes are sent to Trash alongside the folder (membership preserved so
  /// they come back if the folder is restored).
  static Future<void> deleteFolder(String folderId,
      {bool moveNotesToAllNotes = true}) async {
    final db = await database;
    if (moveNotesToAllNotes) {
      await _removeFolderFromNotes(db, folderId);
    } else {
      final notes = await db.query('notes', where: 'is_deleted = 0');
      for (final n in notes) {
        final note = Note.fromMap(n);
        if (note.hasFolder(folderId)) {
          await db.update('notes', {'is_deleted': 1},
              where: 'id = ?', whereArgs: [note.id]);
        }
      }
    }
    await db.update('folders', {'is_deleted': 1},
        where: 'id = ?', whereArgs: [folderId]);
  }

  static Future<void> permanentlyDeleteFolder(String folderId) async {
    final db = await database;
    await _removeFolderFromNotes(db, folderId);
    await db.delete('folders', where: 'id = ?', whereArgs: [folderId]);
  }

  static Future<void> restoreFolder(String folderId) async {
    final db = await database;
    await db.update('folders', {'is_deleted': 0},
        where: 'id = ?', whereArgs: [folderId]);
    // Bring back any notes that were trashed together with this folder.
    final trashed = await db.query('notes', where: 'is_deleted = 1');
    for (final n in trashed) {
      final note = Note.fromMap(n);
      if (note.hasFolder(folderId)) {
        await db.update('notes', {'is_deleted': 0},
            where: 'id = ?', whereArgs: [note.id]);
      }
    }
  }

  static Future<List<Note>> getNotes({String? folderId, String? search}) async {
    final db = await database;
    final conditions = <String>['is_deleted = 0'];
    final args = <dynamic>[];

    if (folderId != null) {
      conditions.add('(folder_id = ? OR folder_id LIKE ?)');
      args.add(folderId);
      args.add('%"$folderId"%');
    }

    if (search != null && search.isNotEmpty) {
      conditions.add('(title LIKE ? OR content LIKE ?)');
      args.add('%$search%');
      args.add('%$search%');
    }

    final maps = await db.query('notes',
        where: conditions.join(' AND '),
        whereArgs: args,
        orderBy: 'is_pinned DESC, modified_at DESC');
    return maps.map((m) => Note.fromMap(m)).toList();
  }

  static Future<List<Note>> getAllNotes({String? search}) async {
    final db = await database;
    final conditions = <String>['is_deleted = 0'];
    final args = <dynamic>[];

    if (search != null && search.isNotEmpty) {
      conditions.add('(title LIKE ? OR content LIKE ?)');
      args.add('%$search%');
      args.add('%$search%');
    }

    final maps = await db.query('notes',
        where: conditions.join(' AND '),
        whereArgs: args,
        orderBy: 'is_pinned DESC, modified_at DESC');
    return maps.map((m) => Note.fromMap(m)).toList();
  }

  static Future<List<Note>> getTrashedNotes() async {
    final db = await database;
    final maps = await db.query('notes',
        where: 'is_deleted = 1', orderBy: 'modified_at DESC');
    return maps.map((m) => Note.fromMap(m)).toList();
  }

  static Future<List<Folder>> getTrashedFolders() async {
    final db = await database;
    final maps = await db.query('folders',
        where: 'is_deleted = 1', orderBy: 'sort_order ASC, name ASC');
    return maps.map((m) => Folder.fromMap(m)).toList();
  }

  static Future<Map<String, int>> getNoteCountsPerFolder() async {
    final db = await database;
    final maps = await db.query('notes', where: 'is_deleted = 0');
    final notes = maps.map((m) => Note.fromMap(m)).toList();
    final result = <String, int>{};
    for (final note in notes) {
      for (final fid in note.folderIds) {
        if (fid.isNotEmpty) {
          result[fid] = (result[fid] ?? 0) + 1;
        }
      }
    }
    return result;
  }

  static Future<int> getTotalNonTrashedNoteCount() async {
    final db = await database;
    final result = await db
        .rawQuery('SELECT COUNT(*) as cnt FROM notes WHERE is_deleted = 0');
    return (result.first['cnt'] as int?) ?? 0;
  }

  static Future<int> getTrashedNoteCount() async {
    final db = await database;
    final result = await db
        .rawQuery('SELECT COUNT(*) as cnt FROM notes WHERE is_deleted = 1');
    return (result.first['cnt'] as int?) ?? 0;
  }

  static Future<int> getTrashedFolderCount() async {
    final db = await database;
    final result = await db
        .rawQuery('SELECT COUNT(*) as cnt FROM folders WHERE is_deleted = 1');
    return (result.first['cnt'] as int?) ?? 0;
  }

  static Future<void> insertNote(Note note) async {
    final db = await database;
    await db.insert('notes', note.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<void> updateNote(Note note) async {
    final db = await database;
    await db.update('notes', note.toMap(),
        where: 'id = ?', whereArgs: [note.id]);
  }

  static Future<void> deleteNote(String noteId) async {
    final db = await database;
    await db.update('notes', {'is_deleted': 1},
        where: 'id = ?', whereArgs: [noteId]);
  }

  static Future<void> permanentlyDeleteNote(String noteId) async {
    final db = await database;
    await db.delete('notes', where: 'id = ?', whereArgs: [noteId]);
  }

  static Future<void> restoreNote(String noteId) async {
    final db = await database;
    await db.update('notes', {'is_deleted': 0},
        where: 'id = ?', whereArgs: [noteId]);
  }

  static Future<void> updateNoteFolder(
      String noteId, List<String> folderIds) async {
    final db = await database;
    final val = folderIds.isNotEmpty ? jsonEncode(folderIds) : null;
    await db.update('notes', {'folder_id': val},
        where: 'id = ?', whereArgs: [noteId]);
  }

  static Future<void> updateNotePin(String noteId, bool isPinned) async {
    final db = await database;
    await db.update('notes', {'is_pinned': isPinned ? 1 : 0},
        where: 'id = ?', whereArgs: [noteId]);
  }

  // ─── Bulk / data-transfer helpers (used by export & import) ───

  static Future<List<Note>> getAllNotesRaw() async {
    final db = await database;
    final maps = await db.query('notes');
    return maps.map((m) => Note.fromMap(m)).toList();
  }

  static Future<List<Folder>> getAllFoldersRaw() async {
    final db = await database;
    final maps = await db.query('folders');
    return maps.map((m) => Folder.fromMap(m)).toList();
  }

  /// Imports notes & folders, replacing any rows with matching ids.
  static Future<void> importData(
      List<Folder> folders, List<Note> notes) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final f in folders) {
        await txn.insert('folders', f.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final n in notes) {
        await txn.insert('notes', n.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }
}
