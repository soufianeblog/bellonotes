import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/note.dart';
import '../models/folder.dart';
import '../providers/folders_provider.dart';
import '../providers/notes_provider.dart';
import '../l10n/strings.dart';

/// A flattened row in the notes list: either a section header or a note.
class _ListRow {
  final String? header;
  final Note? note;
  const _ListRow.header(this.header) : note = null;
  const _ListRow.note(this.note) : header = null;
  bool get isHeader => header != null;
}

class NotesSidebar extends StatelessWidget {
  final bool mobileMode;
  final void Function(Note note)? onNoteTap;

  const NotesSidebar({super.key, this.mobileMode = false, this.onNoteTap});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotesProvider>();
    final notes = provider.isTrashView ? provider.trashedNotes : provider.notes;
    final selectedNote = provider.selectedNote;
    final folderId = provider.selectedFolderId;
    final searchQuery = provider.searchQuery;

    final s = S.of(context);
    final pinned = notes.where((n) => n.isPinned).toList();
    final unpinned = notes.where((n) => !n.isPinned).toList();
    final groups = _groupByDate(unpinned, s);

    String headerText = folderId == 'all' ? s.allNotes : s.notes;
    int count = notes.length;

    if (folderId == 'trash') {
      headerText = s.trash;
    } else if (folderId != 'all') {
      final folders = context.watch<FoldersProvider>().folders;
      final folder = folders.where((f) => f.id == folderId).firstOrNull;
      headerText = folder?.name ?? s.notes;
    }

    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          _buildHeader(context, headerText, count, folderId),
          const Divider(height: 1),
          _buildNotesSearchField(context),
          if (provider.selectionMode) _buildSelectionBar(context, provider),
          if (provider.isTrashView &&
              (notes.isNotEmpty ||
                  context.watch<FoldersProvider>().trashedFolders.isNotEmpty) &&
              !provider.selectionMode)
            _buildTrashActions(context),
          Expanded(
            child: provider.isTrashView
                ? _buildTrashList(context, notes, selectedNote,
                    context.watch<FoldersProvider>().trashedFolders)
                : _buildNotesList(context, pinned, groups, notes,
                    selectedNote, searchQuery),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesSearchField(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: _NotesSearchField(),
    );
  }

  Widget _buildHeader(
      BuildContext context, String title, int count, String folderId) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _EditableFolderTitle(
                  title: title,
                  folderId: folderId,
                  canEdit: folderId != 'all' && folderId != 'trash',
                ),
              ),
              if (folderId != 'all' && folderId != 'trash') ...[
                IconButton(
                  icon: const Icon(Icons.add, size: 18),
                  tooltip: S.of(context).newNote,
                  onPressed: () async {
                    await context
                        .read<NotesProvider>()
                        .createNote(folderId: folderId);
                    if (context.mounted) {
                      context.read<FoldersProvider>().refreshCounts();
                    }
                  },
                  padding: const EdgeInsets.all(4),
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  iconSize: 16,
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 16),
                  tooltip: 'Rename Folder',
                  onPressed: () {
                    final foldersProvider = context.read<FoldersProvider>();
                    final folder = foldersProvider.folders
                        .where((f) => f.id == folderId)
                        .firstOrNull;
                    if (folder != null) {
                      _showRenameDialog(context, folder);
                    }
                  },
                  padding: const EdgeInsets.all(4),
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  iconSize: 15,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16),
                  tooltip: 'Delete Folder',
                  onPressed: () {
                    final foldersProvider = context.read<FoldersProvider>();
                    final folder = foldersProvider.folders
                        .where((f) => f.id == folderId)
                        .firstOrNull;
                    if (folder != null) {
                      _confirmDeleteFolder(
                          context, folder, foldersProvider);
                    }
                  },
                  padding: const EdgeInsets.all(4),
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  iconSize: 15,
                ),
              ],
              IconButton(
                icon: const Icon(Icons.checklist, size: 16),
                tooltip: S.of(context).selectItems,
                onPressed: () =>
                    context.read<NotesProvider>().toggleSelectionMode(),
                padding: const EdgeInsets.all(4),
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
                iconSize: 15,
              ),
              if (folderId != 'trash')
                GestureDetector(
                  onTapDown: (details) => _showSortMenu(context, details),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    child: const Icon(Icons.sort, size: 15),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '$count ${count == 1 ? S.of(context).noteCount : S.of(context).notesCount}',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionBar(BuildContext context, NotesProvider provider) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final isTrash = provider.isTrashView;
    return Container(
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.35),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(children: [
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          tooltip: s.cancel,
          visualDensity: VisualDensity.compact,
          onPressed: provider.clearSelection,
        ),
        Text('${provider.selectedCount} ${s.selected}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const Spacer(),
        if (isTrash) ...[
          IconButton(
            icon: const Icon(Icons.restore, size: 18),
            tooltip: s.restore,
            visualDensity: VisualDensity.compact,
            onPressed: provider.selectedCount == 0
                ? null
                : () async {
                    await provider.restoreSelected();
                    if (context.mounted) {
                      context.read<FoldersProvider>().refreshCounts();
                    }
                  },
          ),
          IconButton(
            icon: Icon(Icons.delete_forever,
                size: 18, color: theme.colorScheme.error),
            tooltip: s.deleteForever,
            visualDensity: VisualDensity.compact,
            onPressed: provider.selectedCount == 0
                ? null
                : provider.permanentlyDeleteSelected,
          ),
        ] else ...[
          IconButton(
            icon: const Icon(Icons.drive_file_move_outlined, size: 18),
            tooltip: s.moveToFolder,
            visualDensity: VisualDensity.compact,
            onPressed: provider.selectedCount == 0
                ? null
                : () => _showBulkMoveDialog(context, provider),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline,
                size: 18, color: theme.colorScheme.error),
            tooltip: s.delete,
            visualDensity: VisualDensity.compact,
            onPressed: provider.selectedCount == 0
                ? null
                : () async {
                    await provider.deleteSelected();
                    if (context.mounted) {
                      context.read<FoldersProvider>().refreshCounts();
                    }
                  },
          ),
        ],
      ]),
    );
  }

  void _showBulkMoveDialog(BuildContext context, NotesProvider provider) {
    final s = S.of(context);
    final folders = context.read<FoldersProvider>().folders;
    final selected = <String>{};
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(s.moveToFolder),
          content: SizedBox(
            width: 300,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ...folders.map((f) => CheckboxListTile(
                    title: Text(f.name),
                    value: selected.contains(f.id),
                    onChanged: (v) => setLocal(() {
                      if (v == true) {
                        selected.add(f.id);
                      } else {
                        selected.remove(f.id);
                      }
                    }),
                  )),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await provider.moveSelectedToFolder(selected.toList());
                if (context.mounted) {
                  context.read<FoldersProvider>().refreshCounts();
                }
              },
              child: Text(s.ok),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrashActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(children: [
        SizedBox(
          width: double.infinity,
          height: 40,
          child: FilledButton.icon(
            onPressed: () async {
              final provider = context.read<NotesProvider>();
              final foldersProvider = context.read<FoldersProvider>();
              final notes = List<Note>.from(provider.trashedNotes);
              for (final n in notes) {
                provider.restoreNote(n.id);
              }
              await foldersProvider.restoreAllTrashedFolders();
              await foldersProvider.refreshCounts();
            },
            icon: const Icon(Icons.restore, size: 16),
            label: Text(S.of(context).restoreAll,
                style: const TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          height: 40,
          child: FilledButton.icon(
            onPressed: () => _confirmEmptyTrash(context),
            icon: const Icon(Icons.delete_forever, size: 16),
            label: Text(S.of(context).emptyTrash,
                style: const TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ]),
    );
  }

  void _confirmEmptyTrash(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Empty Trash'),
        content: const Text(
            'Permanently delete all notes in Trash? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () async {
              final provider = context.read<NotesProvider>();
              final foldersProvider = context.read<FoldersProvider>();
              final nav = Navigator.of(ctx);
              final notes = List<Note>.from(provider.trashedNotes);
              for (final n in notes) {
                provider.permanentlyDeleteNote(n.id);
              }
              await foldersProvider.permanentlyDeleteAllTrashedFolders();
              nav.pop();
            },
            child: Text(S.of(context).emptyTrash),
          ),
        ],
      ),
    );
  }

  void _showSortMenu(BuildContext context, TapDownDetails details) {
    final provider = context.read<NotesProvider>();
    final currentSort = provider.sortOrder;
    String? currentValue;
    switch (currentSort) {
      case NotesSortOrder.dateNewest: currentValue = 'date_newest';
      case NotesSortOrder.dateOldest: currentValue = 'date_oldest';
      case NotesSortOrder.titleAz: currentValue = 'title_az';
      case NotesSortOrder.titleZa: currentValue = 'title_za';
    }
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        details.globalPosition.dx,
        details.globalPosition.dy,
        details.globalPosition.dx,
        details.globalPosition.dy,
      ),
      items: [
        PopupMenuItem(
          value: 'date_newest',
          child: Row(children: [
            SizedBox(
                width: 20,
                child: currentValue == 'date_newest'
                    ? const Icon(Icons.check, size: 16)
                    : null),
            const Text('Date Modified (Newest)'),
          ]),
        ),
        PopupMenuItem(
          value: 'date_oldest',
          child: Row(children: [
            SizedBox(
                width: 20,
                child: currentValue == 'date_oldest'
                    ? const Icon(Icons.check, size: 16)
                    : null),
            const Text('Date Modified (Oldest)'),
          ]),
        ),
        PopupMenuItem(
          value: 'title_az',
          child: Row(children: [
            SizedBox(
                width: 20,
                child: currentValue == 'title_az'
                    ? const Icon(Icons.check, size: 16)
                    : null),
            const Text('Title (A-Z)'),
          ]),
        ),
        PopupMenuItem(
          value: 'title_za',
          child: Row(children: [
            SizedBox(
                width: 20,
                child: currentValue == 'title_za'
                    ? const Icon(Icons.check, size: 16)
                    : null),
            const Text('Title (Z-A)'),
          ]),
        ),
      ],
    ).then((value) {
      if (!context.mounted) return;
      switch (value) {
        case 'date_newest':
          provider.sortNotes(NotesSortOrder.dateNewest);
          break;
        case 'date_oldest':
          provider.sortNotes(NotesSortOrder.dateOldest);
          break;
        case 'title_az':
          provider.sortNotes(NotesSortOrder.titleAz);
          break;
        case 'title_za':
          provider.sortNotes(NotesSortOrder.titleZa);
          break;
      }
    });
  }

  void _showRenameDialog(BuildContext context, Folder folder) {
    final controller = TextEditingController(text: folder.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Folder name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) {
              context.read<FoldersProvider>().renameFolder(folder, v.trim());
              Navigator.pop(ctx);
            }
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                context
                    .read<FoldersProvider>()
                    .renameFolder(folder, controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteFolder(
      BuildContext context,
      Folder folder,
      FoldersProvider foldersProvider) {
    final s = S.of(context);
    bool moveToAll = true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('${s.delete} — ${folder.name}'),
          content: CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: moveToAll,
            onChanged: (v) => setLocal(() => moveToAll = v ?? true),
            title:
                Text(s.moveNotesToAllNotes, style: const TextStyle(fontSize: 14)),
            subtitle: Text(
                moveToAll ? s.notesKeptInAllNotes : s.notesSentToTrash,
                style: const TextStyle(fontSize: 12)),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () {
                foldersProvider.deleteFolder(folder,
                    moveNotesToAllNotes: moveToAll);
                context.read<NotesProvider>().loadNotes(folderId: 'all');
                Navigator.pop(ctx);
              },
              child: Text(s.delete),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotesList(
    BuildContext context,
    List<Note> pinned,
    Map<String, List<Note>> groups,
    List<Note> notes,
    Note? selectedNote,
    String searchQuery,
  ) {
    final s = S.of(context);
    if (notes.isEmpty) {
      return _emptyMessage(
        context,
        searchQuery.isNotEmpty ? Icons.search_off : Icons.notes,
        searchQuery.isNotEmpty ? s.noNotesFound : s.noNotesFound,
      );
    }

    // Flatten into a single row list so ListView.builder can lazily render —
    // critical for fast folder switching with many notes.
    final rows = <_ListRow>[];
    if (pinned.isNotEmpty) {
      rows.add(_ListRow.header(s.pinned));
      rows.addAll(pinned.map((n) => _ListRow.note(n)));
    }
    for (final entry in groups.entries) {
      rows.add(_ListRow.header(entry.key));
      rows.addAll(entry.value.map((n) => _ListRow.note(n)));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        if (row.isHeader) {
          return _buildSectionHeader(context, row.header!);
        }
        final n = row.note!;
        return _buildNoteItem(context, n,
            selected: selectedNote?.id == n.id, searchQuery: searchQuery);
      },
    );
  }

  Widget _emptyMessage(BuildContext context, IconData icon, String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 32,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.3)),
            const SizedBox(height: 8),
            Text(msg,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildTrashList(BuildContext context, List<Note> notes,
      Note? selectedNote, List<Folder> trashedFolders) {
    final s = S.of(context);
    if (notes.isEmpty && trashedFolders.isEmpty) {
      return _emptyMessage(context, Icons.delete_outline, s.trashEmpty);
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        if (trashedFolders.isNotEmpty) ...[
          _buildSectionHeader(context, s.folders),
          ...trashedFolders.map((f) => _buildTrashedFolderItem(context, f)),
          const SizedBox(height: 8),
        ],
        if (notes.isNotEmpty) _buildSectionHeader(context, s.notes),
        ...notes.map((n) => _buildNoteItem(context, n,
            selected: selectedNote?.id == n.id, showTrashActions: true)),
      ],
    );
  }

  Widget _buildTrashedFolderItem(BuildContext context, Folder folder) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(children: [
        Icon(Icons.folder_outlined,
            size: 18, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(folder.name,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis),
        ),
        IconButton(
          icon: const Icon(Icons.restore, size: 16),
          tooltip: S.of(context).restore,
          visualDensity: VisualDensity.compact,
          onPressed: () async {
            await context.read<FoldersProvider>().restoreFolder(folder.id);
            if (!context.mounted) return;
            await context.read<FoldersProvider>().loadTrash();
            if (!context.mounted) return;
            context.read<NotesProvider>().loadTrash();
          },
        ),
        IconButton(
          icon: Icon(Icons.delete_forever,
              size: 16, color: theme.colorScheme.error),
          tooltip: S.of(context).deleteForever,
          visualDensity: VisualDensity.compact,
          onPressed: () =>
              context.read<FoldersProvider>().permanentlyDeleteFolder(folder.id),
        ),
      ]),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildNoteItem(
    BuildContext context,
    Note note, {
    bool selected = false,
    bool showTrashActions = false,
    String searchQuery = '',
  }) {
    final theme = Theme.of(context);
    final provider = context.watch<NotesProvider>();
    final selectionMode = provider.selectionMode;
    final checked = provider.isSelected(note.id);
    final bgColor = (selected || checked)
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
        : Colors.transparent;
    final fgColor = (selected || checked)
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    final s = S.of(context);
    var title = note.displayTitle;
    if (title.isEmpty) title = s.newNote;
    final snippet = note.snippet;
    final subtitle = snippet.isNotEmpty ? snippet : s.noAdditionalText;
    final displaySubtitle = _buildSearchSnippet(subtitle, searchQuery);

    final now = DateTime.now();
    final m = note.modifiedAt;
    final sameDay = m.year == now.year && m.month == now.month && m.day == now.day;
    final dateStr = sameDay
        ? DateFormat.Hm(S.of(context).lang).format(m)
        : DateFormat.yMMMd(S.of(context).lang).add_Hm().format(m);

    return GestureDetector(
      onTap: () {
        final p = context.read<NotesProvider>();
        if (selectionMode) {
          p.toggleSelected(note.id);
          return;
        }
        p.selectNote(note);
        if (mobileMode && onNoteTap != null) {
          onNoteTap!(note);
        }
      },
      onLongPressStart: (d) =>
          _showNoteContextMenu(context, note, d.globalPosition, showTrashActions),
      onSecondaryTapDown: (d) =>
          _showNoteContextMenu(context, note, d.globalPosition, showTrashActions),
      child: Container(
        color: bgColor,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selectionMode)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  checked
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color: checked
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (note.isPinned && !showTrashActions && !selectionMode)
              Padding(
                padding: const EdgeInsets.only(right: 6, top: 2),
                child: Icon(Icons.push_pin, size: 14, color: fgColor),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHighlightedText(context, title, searchQuery,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: fgColor,
                      ),
                      maxLines: 1),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: _buildHighlightedText(
                            context, displaySubtitle, searchQuery,
                            style: TextStyle(
                              fontSize: 11,
                              color: fgColor.withValues(alpha: 0.6),
                            ),
                            maxLines: 1),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 10,
                          color: fgColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNoteContextMenu(BuildContext context, Note note, Offset position,
      bool inTrash) {
    final s = S.of(context);
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final notes = context.read<NotesProvider>();
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
          position & const Size(40, 40), Offset.zero & overlay.size),
      items: [
        if (!inTrash) ...[
          PopupMenuItem(value: 'pin', child: Text(note.isPinned ? s.unpin : s.pin)),
          PopupMenuItem(value: 'move', child: Text(s.moveToFolder)),
          PopupMenuItem(value: 'select', child: Text(s.selectItems)),
          PopupMenuItem(
              value: 'delete',
              child: Text(s.delete,
                  style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ] else ...[
          PopupMenuItem(value: 'restore', child: Text(s.restore)),
          PopupMenuItem(value: 'select', child: Text(s.selectItems)),
          PopupMenuItem(
              value: 'forever',
              child: Text(s.deleteForever,
                  style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ],
      ],
    ).then((value) {
      if (!context.mounted) return;
      switch (value) {
        case 'pin':
          notes.togglePin(note);
          break;
        case 'move':
          notes.enterSelection(note.id);
          _showBulkMoveDialog(context, notes);
          break;
        case 'select':
          notes.enterSelection(note.id);
          break;
        case 'delete':
          notes.deleteNote(note);
          context.read<FoldersProvider>().refreshCounts();
          break;
        case 'restore':
          notes.restoreNote(note.id);
          context.read<FoldersProvider>().refreshCounts();
          break;
        case 'forever':
          notes.permanentlyDeleteNote(note.id);
          break;
      }
    });
  }

  Widget _buildHighlightedText(
      BuildContext context, String text, String query,
      {TextStyle? style, int? maxLines}) {
    if (query.isEmpty) {
      return Text(text,
          style: style, overflow: TextOverflow.ellipsis, maxLines: maxLines);
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final idx = lowerText.indexOf(lowerQuery, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start), style: style));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(
            text: text.substring(start, idx), style: style));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + query.length),
        style: (style ?? const TextStyle()).copyWith(
          backgroundColor: Colors.yellow.withValues(alpha: 0.4),
          fontWeight: FontWeight.bold,
        ),
      ));
      start = idx + query.length;
    }

    return RichText(
      text: TextSpan(children: spans),
      overflow: TextOverflow.ellipsis,
      maxLines: maxLines ?? 1,
    );
  }

  String _buildSearchSnippet(String text, String query) {
    if (query.isEmpty) {
      return text.length > 50 ? '${text.substring(0, 50)}...' : text;
    }
    final idx = text.toLowerCase().indexOf(query.toLowerCase());
    if (idx == -1) {
      return text.length > 50 ? '${text.substring(0, 50)}...' : text;
    }
    const radius = 40;
    int start = (idx - radius).clamp(0, text.length);
    int end = (idx + query.length + radius).clamp(0, text.length);
    if (start > 0) start = text.indexOf(' ', start);
    if (start < 0) start = 0;
    if (end < text.length) {
      final nextSpace = text.indexOf(' ', end);
      if (nextSpace > 0 && nextSpace < end + 20) end = nextSpace;
    }
    final before = start > 0 ? '...' : '';
    final after = end < text.length ? '...' : '';
    return '$before${text.substring(start, end)}$after';
  }

  Map<String, List<Note>> _groupByDate(List<Note> notes, S s) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final sevenDaysAgo = today.subtract(const Duration(days: 7));
    final thirtyDaysAgo = today.subtract(const Duration(days: 30));

    final groups = <String, List<Note>>{};
    final monthFormat = DateFormat.yMMMM(s.lang);

    for (final note in notes) {
      final date = DateTime(
          note.modifiedAt.year, note.modifiedAt.month, note.modifiedAt.day);
      String group;

      if (date == today) {
        group = s.today;
      } else if (date == yesterday) {
        group = s.yesterday;
      } else if (date.isAfter(sevenDaysAgo)) {
        group = s.previous7;
      } else if (date.isAfter(thirtyDaysAgo)) {
        group = s.previous30;
      } else {
        group = monthFormat.format(date);
      }

      groups.putIfAbsent(group, () => []).add(note);
    }

    return groups;
  }
}

class _NotesSearchField extends StatefulWidget {
  const _NotesSearchField();

  @override
  State<_NotesSearchField> createState() => _NotesSearchFieldState();
}

class _NotesSearchFieldState extends State<_NotesSearchField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    final query = context.watch<NotesProvider>().searchQuery;
    // Keep the field in sync when search is cleared externally (folder switch).
    if (!_focus.hasFocus && _controller.text != query) {
      _controller.text = query;
    }
    return SizedBox(
      height: 34,
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: s.searchNotes,
          prefixIcon: const Icon(Icons.search, size: 16),
          suffixIcon: query.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 14),
                  onPressed: () {
                    _controller.clear();
                    context.read<NotesProvider>().searchNotes('');
                  },
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          filled: true,
          fillColor: theme.colorScheme.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
                color: theme.colorScheme.outline.withValues(alpha: 0.2)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
                color: theme.colorScheme.outline.withValues(alpha: 0.2)),
          ),
        ),
        onChanged: (v) => context.read<NotesProvider>().searchNotes(v),
      ),
    );
  }
}

class _EditableFolderTitle extends StatefulWidget {
  final String title;
  final String folderId;
  final bool canEdit;

  const _EditableFolderTitle({
    required this.title,
    required this.folderId,
    required this.canEdit,
  });

  @override
  State<_EditableFolderTitle> createState() => _EditableFolderTitleState();
}

class _EditableFolderTitleState extends State<_EditableFolderTitle> {
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    if (_editing && widget.canEdit) {
      final controller = TextEditingController(text: widget.title);
      return TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        onSubmitted: (v) => _commit(v),
        onTapOutside: (_) => _commit(controller.text),
      );
    }

    return GestureDetector(
      onTap: widget.canEdit ? () => setState(() => _editing = true) : null,
      child: Text(
        widget.title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  void _commit(String newName) {
    setState(() => _editing = false);
    if (newName.trim().isNotEmpty &&
        newName.trim() != widget.title &&
        widget.canEdit) {
      final foldersProvider = context.read<FoldersProvider>();
      final folder = foldersProvider.folders
          .where((f) => f.id == widget.folderId)
          .firstOrNull;
      if (folder != null) {
        foldersProvider.renameFolder(folder, newName.trim());
      }
    }
  }
}
