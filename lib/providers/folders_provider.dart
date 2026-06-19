// ChangeNotifier that owns the folder list, per-folder note counts, the trash,
// and folder multi-selection state. Persists every mutation through
// [DatabaseService] and notifies the UI.
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/folder.dart';
import '../services/database_service.dart';

class FoldersProvider extends ChangeNotifier {
  List<Folder> _folders = [];
  List<Folder> _trashedFolders = [];
  Map<String, int> _folderNoteCounts = {};
  final Uuid _uuid = const Uuid();

  List<Folder> get folders => _folders;
  List<Folder> get trashedFolders => _trashedFolders;
  Map<String, int> get folderNoteCounts => _folderNoteCounts;

  int getNoteCountForFolder(String folderId) =>
      _folderNoteCounts[folderId] ?? 0;

  Future<void> loadFolders() async {
    _folders = await DatabaseService.getFolders();
    _folderNoteCounts = await DatabaseService.getNoteCountsPerFolder();
    notifyListeners();
  }

  Future<void> refreshCounts() async {
    _folderNoteCounts = await DatabaseService.getNoteCountsPerFolder();
    notifyListeners();
  }

  Future<Folder> createFolder(String name) async {
    final folder = Folder(
      id: _uuid.v4(),
      name: name,
      createdAt: DateTime.now(),
      sortOrder: _folders.length,
    );
    await DatabaseService.insertFolder(folder);
    _folders.add(folder);
    _folderNoteCounts[folder.id] = 0;
    notifyListeners();
    return folder;
  }

  Future<void> renameFolder(Folder folder, String newName) async {
    final updated = folder.copyWith(name: newName);
    await DatabaseService.updateFolder(updated);
    final idx = _folders.indexWhere((f) => f.id == folder.id);
    if (idx != -1) _folders[idx] = updated;
    notifyListeners();
  }

  Future<void> deleteFolder(Folder folder,
      {bool moveNotesToAllNotes = true}) async {
    await DatabaseService.deleteFolder(folder.id,
        moveNotesToAllNotes: moveNotesToAllNotes);
    _folders.removeWhere((f) => f.id == folder.id);
    _folderNoteCounts.remove(folder.id);
    notifyListeners();
  }

  Future<void> permanentlyDeleteFolder(String folderId) async {
    await DatabaseService.permanentlyDeleteFolder(folderId);
    _trashedFolders.removeWhere((f) => f.id == folderId);
    notifyListeners();
  }

  Future<void> restoreFolder(String folderId) async {
    await DatabaseService.restoreFolder(folderId);
    _folders = await DatabaseService.getFolders();
    _folderNoteCounts = await DatabaseService.getNoteCountsPerFolder();
    _trashedFolders.removeWhere((f) => f.id == folderId);
    notifyListeners();
  }

  /// Restores every folder currently in Trash.
  Future<void> restoreAllTrashedFolders() async {
    final ids = _trashedFolders.map((f) => f.id).toList();
    for (final id in ids) {
      await DatabaseService.restoreFolder(id);
    }
    _folders = await DatabaseService.getFolders();
    _folderNoteCounts = await DatabaseService.getNoteCountsPerFolder();
    _trashedFolders.clear();
    notifyListeners();
  }

  /// Permanently deletes every folder currently in Trash.
  Future<void> permanentlyDeleteAllTrashedFolders() async {
    final ids = _trashedFolders.map((f) => f.id).toList();
    for (final id in ids) {
      await DatabaseService.permanentlyDeleteFolder(id);
    }
    _trashedFolders.clear();
    notifyListeners();
  }

  Future<void> loadTrash() async {
    _trashedFolders = await DatabaseService.getTrashedFolders();
    notifyListeners();
  }

  int get totalActiveFolders => _folders.length;
  int get trashedFolderCount => _trashedFolders.length;

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

  /// Toggles selection mode on/off without preselecting a folder. Used by the
  /// select-mode button next to the folder sort control.
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

  Future<void> deleteSelected({bool moveNotesToAllNotes = true}) async {
    final ids = List<String>.from(_selectedIds);
    for (final id in ids) {
      await DatabaseService.deleteFolder(id,
          moveNotesToAllNotes: moveNotesToAllNotes);
    }
    _folders.removeWhere((f) => ids.contains(f.id));
    for (final id in ids) {
      _folderNoteCounts.remove(id);
    }
    clearSelection();
  }
}
