// ChangeNotifier that owns the in-memory note list and the current selection,
// search query and folder filter. It is the UI's single source of truth for
// notes and persists every mutation through [DatabaseService].
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import '../services/database_service.dart';

enum NotesSortOrder { dateNewest, dateOldest, titleAz, titleZa }

class NotesProvider extends ChangeNotifier {
  List<Note> _notes = [];
  List<Note> _trashedNotes = [];
  Note? _selectedNote;
  String _selectedFolderId = 'all';
  String _searchQuery = '';
  int _totalCount = 0;
  NotesSortOrder _sortOrder = NotesSortOrder.dateNewest;
  NotesSortOrder get sortOrder => _sortOrder;

  final Uuid _uuid = const Uuid();

  VoidCallback? onFoldersNeedRefresh;
  void Function(NotesSortOrder order)? onSortChanged;

  void setInitialSort(NotesSortOrder order) {
    _sortOrder = order;
  }

  List<Note> get notes => _notes;
  List<Note> get trashedNotes => _trashedNotes;
  Note? get selectedNote => _selectedNote;
  String get selectedFolderId => _selectedFolderId;
  String get searchQuery => _searchQuery;
  int get noteCount => _totalCount;
  int get trashedNoteCount => _trashedNotes.length;

  List<Note> get pinnedNotes =>
      _notes.where((n) => n.isPinned).toList();
  List<Note> get unpinnedNotes =>
      _notes.where((n) => !n.isPinned).toList();

  Future<void> loadNotes(
      {String? folderId, String? search, bool clearSelection = false}) async {
    _selectedFolderId = folderId ?? 'all';
    _searchQuery = search ?? '';
    if (clearSelection) _selectedNote = null;
    if (_selectedFolderId == 'trash') {
      _trashedNotes = await DatabaseService.getTrashedNotes();
      _applySort(_trashedNotes);
      _notes = [];
    } else {
      _notes = _selectedFolderId == 'all'
          ? await DatabaseService.getAllNotes(search: _searchQuery)
          : await DatabaseService.getNotes(
              folderId: _selectedFolderId, search: _searchQuery);
      _applySort(_notes);
      _totalCount = await DatabaseService.getTotalNonTrashedNoteCount();
    }
    notifyListeners();
  }

  Future<void> searchNotes(String query) async {
    _searchQuery = query;
    if (_selectedFolderId == 'trash') {
      _trashedNotes = await DatabaseService.getTrashedNotes();
      _applySort(_trashedNotes);
    } else {
      _notes = _selectedFolderId == 'all'
          ? await DatabaseService.getAllNotes(search: _searchQuery)
          : await DatabaseService.getNotes(
              folderId: _selectedFolderId, search: _searchQuery);
      _applySort(_notes);
    }
    notifyListeners();
  }

  void selectNote(Note? note) {
    _selectedNote = note;
    notifyListeners();
  }

  void sortNotes(NotesSortOrder order) {
    _sortOrder = order;
    _applySort(_notes);
    _applySort(_trashedNotes);
    notifyListeners();
    onSortChanged?.call(order);
  }

  void _applySort(List<Note> list) {
    switch (_sortOrder) {
      case NotesSortOrder.dateNewest:
        list.sort((a, b) {
          if (a.isPinned && !b.isPinned) return -1;
          if (!a.isPinned && b.isPinned) return 1;
          return b.modifiedAt.compareTo(a.modifiedAt);
        });
        break;
      case NotesSortOrder.dateOldest:
        list.sort((a, b) {
          if (a.isPinned && !b.isPinned) return -1;
          if (!a.isPinned && b.isPinned) return 1;
          return a.modifiedAt.compareTo(b.modifiedAt);
        });
        break;
      case NotesSortOrder.titleAz:
        list.sort((a, b) {
          if (a.isPinned && !b.isPinned) return -1;
          if (!a.isPinned && b.isPinned) return 1;
          return a.title.compareTo(b.title);
        });
        break;
      case NotesSortOrder.titleZa:
        list.sort((a, b) {
          if (a.isPinned && !b.isPinned) return -1;
          if (!a.isPinned && b.isPinned) return 1;
          return b.title.compareTo(a.title);
        });
        break;
    }
  }

  Future<Note> createNote({String? folderId}) async {
    final now = DateTime.now();
    final folderIds = folderId != null ? [folderId] : <String>[];
    final note = Note(
      id: _uuid.v4(),
      title: '',
      content: '',
      folderIds: folderIds,
      createdAt: now,
      modifiedAt: now,
    );
    await DatabaseService.insertNote(note);
    _totalCount++;

    if (_selectedFolderId == 'all' ||
        folderId == _selectedFolderId ||
        folderId == null) {
      _notes.insert(0, note);
      _applySort(_notes);
    }
    _selectedNote = note;
    notifyListeners();
    return note;
  }

  Future<void> updateNoteContent(Note note, String content) async {
    final updated = note.copyWith(
      content: content,
      modifiedAt: DateTime.now(),
      title: _extractTitle(content),
    );
    await DatabaseService.updateNote(updated);
    final idx = _notes.indexWhere((n) => n.id == note.id);
    if (idx != -1) {
      _notes[idx] = updated;
      if (_selectedNote?.id == note.id) _selectedNote = updated;
    }
    notifyListeners();
  }

  String _extractTitle(String content) {
    if (content.isEmpty) return '';

    // Try Delta JSON first — extract text from insert ops until first newline
    final plain = _deltaToPlainTitle(content);
    if (plain.isNotEmpty && plain.length <= 100) return plain;
    if (plain.length > 100) return plain.substring(0, 100);

    // Fallback: plain text / markdown — strip formatting from lines
    final lines = content.trim().split('\n');
    for (final line in lines) {
      final trimmed = _sanitizeLine(line);
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  String _deltaToPlainTitle(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is! List) return '';
      final sb = StringBuffer();
      for (final op in decoded) {
        if (op is Map && op.containsKey('insert')) {
          final insert = op['insert'];
          if (insert is String) {
            sb.write(insert);
            if (insert.contains('\n')) break;
          }
        }
      }
      return sb.toString().split('\n').first.trim();
    } catch (_) {
      return '';
    }
  }

  String _sanitizeLine(String line) {
    return line
        .replaceAll(RegExp(r'^#+\s*'), '')
        .replaceAll(RegExp(r'\*\*?(.+?)\*\*?'), r'$1')
        .replaceAll(RegExp(r'~~(.+?)~~'), r'$1')
        .replaceAll(RegExp(r'`(.+?)`'), r'$1')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'\[([^\]]+)\]\([^)]+\)'), r'$1')
        .replaceAll(RegExp(r"[#*>`~_|\\\-\[\]\{\}" "'" r'":,]+'), ' ')
        .trim();
  }

  Future<void> togglePin(Note note) async {
    final updated = note.copyWith(isPinned: !note.isPinned);
    await DatabaseService.updateNotePin(note.id, updated.isPinned);
    final idx = _notes.indexWhere((n) => n.id == note.id);
    if (idx != -1) {
      _notes[idx] = updated;
      if (_selectedNote?.id == note.id) _selectedNote = updated;
    }
    _applySort(_notes);
    notifyListeners();
  }

  Future<void> moveNoteToFolder(Note note, List<String> folderIds) async {
    await DatabaseService.updateNoteFolder(note.id, folderIds);
    if (_selectedFolderId != 'all' &&
        !folderIds.contains(_selectedFolderId)) {
      _notes.removeWhere((n) => n.id == note.id);
      if (_selectedNote?.id == note.id) _selectedNote = null;
    } else {
      final idx = _notes.indexWhere((n) => n.id == note.id);
      if (idx != -1) _notes[idx] = note.copyWith(folderIds: folderIds);
    }
    notifyListeners();
    onFoldersNeedRefresh?.call();
  }

  Future<void> deleteNote(Note note) async {
    await DatabaseService.deleteNote(note.id);
    _notes.removeWhere((n) => n.id == note.id);
    _totalCount--;
    _trashedNotes = await DatabaseService.getTrashedNotes();
    if (_selectedNote?.id == note.id) {
      _selectedNote = _notes.isNotEmpty ? _notes[0] : null;
    }
    notifyListeners();
    onFoldersNeedRefresh?.call();
  }

  Future<void> permanentlyDeleteNote(String noteId) async {
    await DatabaseService.permanentlyDeleteNote(noteId);
    _trashedNotes.removeWhere((n) => n.id == noteId);
    if (_selectedNote?.id == noteId) {
      _selectedNote = _trashedNotes.isNotEmpty ? _trashedNotes[0] : null;
    }
    notifyListeners();
  }

  Future<void> restoreNote(String noteId) async {
    await DatabaseService.restoreNote(noteId);
    _trashedNotes.removeWhere((n) => n.id == noteId);
    _totalCount++;
    if (_selectedNote?.id == noteId) _selectedNote = null;
    notifyListeners();
    onFoldersNeedRefresh?.call();
  }

  Future<void> loadTrash() async {
    _selectedFolderId = 'trash';
    _searchQuery = '';
    _trashedNotes = await DatabaseService.getTrashedNotes();
    _notes = [];
    notifyListeners();
  }

  bool get isTrashView => _selectedFolderId == 'trash';

  // ─── MULTI-SELECT ───

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  bool get selectionMode => _selectionMode;
  Set<String> get selectedIds => _selectedIds;
  int get selectedCount => _selectedIds.length;
  bool isSelected(String id) => _selectedIds.contains(id);

  void enterSelection(String id) {
    _selectionMode = true;
    _selectedIds.add(id);
    notifyListeners();
  }

  void toggleSelectionMode() {
    _selectionMode = !_selectionMode;
    if (!_selectionMode) _selectedIds.clear();
    notifyListeners();
  }

  void toggleSelected(String id) {
    if (_selectedIds.contains(id)) {
      _selectedIds.remove(id);
    } else {
      _selectedIds.add(id);
    }
    if (_selectedIds.isEmpty) _selectionMode = false;
    notifyListeners();
  }

  void clearSelection() {
    _selectedIds.clear();
    _selectionMode = false;
    notifyListeners();
  }

  void selectAll(Iterable<String> ids) {
    _selectionMode = true;
    _selectedIds.addAll(ids);
    notifyListeners();
  }

  Future<void> deleteSelected() async {
    final ids = List<String>.from(_selectedIds);
    for (final id in ids) {
      await DatabaseService.deleteNote(id);
    }
    _notes.removeWhere((n) => ids.contains(n.id));
    _totalCount = (_totalCount - ids.length).clamp(0, 1 << 31);
    _trashedNotes = await DatabaseService.getTrashedNotes();
    if (_selectedNote != null && ids.contains(_selectedNote!.id)) {
      _selectedNote = null;
    }
    clearSelection();
    onFoldersNeedRefresh?.call();
  }

  Future<void> moveSelectedToFolder(List<String> folderIds) async {
    final ids = List<String>.from(_selectedIds);
    for (final id in ids) {
      await DatabaseService.updateNoteFolder(id, folderIds);
    }
    if (_selectedFolderId != 'all' &&
        !folderIds.contains(_selectedFolderId)) {
      _notes.removeWhere((n) => ids.contains(n.id));
    } else {
      for (final id in ids) {
        final idx = _notes.indexWhere((n) => n.id == id);
        if (idx != -1) _notes[idx] = _notes[idx].copyWith(folderIds: folderIds);
      }
    }
    clearSelection();
    onFoldersNeedRefresh?.call();
  }

  /// Bulk actions for the trash view.
  Future<void> restoreSelected() async {
    final ids = List<String>.from(_selectedIds);
    for (final id in ids) {
      await DatabaseService.restoreNote(id);
    }
    _trashedNotes.removeWhere((n) => ids.contains(n.id));
    _totalCount += ids.length;
    clearSelection();
    onFoldersNeedRefresh?.call();
  }

  Future<void> permanentlyDeleteSelected() async {
    final ids = List<String>.from(_selectedIds);
    for (final id in ids) {
      await DatabaseService.permanentlyDeleteNote(id);
    }
    _trashedNotes.removeWhere((n) => ids.contains(n.id));
    clearSelection();
  }
}
