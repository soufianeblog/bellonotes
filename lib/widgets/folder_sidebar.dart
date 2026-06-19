// Left navigation sidebar: search, the folder list (with sorting, rename,
// multi-select and delete), the All Notes / Trash entries, and the Settings &
// About items. Used directly on desktop and inside a drawer on tablet/mobile.
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/folder.dart';
import '../providers/folders_provider.dart';
import '../providers/notes_provider.dart';
import '../screens/settings_screen.dart';
import '../screens/about_screen.dart';
import '../l10n/strings.dart';

enum FolderSort { nameAz, nameZa, dateNewest, dateOldest, count }

class FolderSidebar extends StatefulWidget {
  final VoidCallback? onNavigate;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenAbout;

  /// Called after the "new note" button creates a note, so the host (mobile)
  /// can open the editor. Null on desktop, where the editor is already shown
  /// in the right pane.
  final VoidCallback? onNoteCreated;

  const FolderSidebar(
      {super.key,
      this.onNavigate,
      this.onOpenSettings,
      this.onOpenAbout,
      this.onNoteCreated});

  @override
  State<FolderSidebar> createState() => _FolderSidebarState();
}

class _FolderSidebarState extends State<FolderSidebar> {
  String? _editingFolderId;
  final TextEditingController _searchController = TextEditingController();
  String _folderQuery = '';
  FolderSort _folderSort = FolderSort.nameAz;

  List<Folder> _sortFolders(List<Folder> folders) {
    final list = List<Folder>.from(folders);
    final counts = context.read<FoldersProvider>().folderNoteCounts;
    switch (_folderSort) {
      case FolderSort.nameAz:
        list.sort((a, b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case FolderSort.nameZa:
        list.sort((a, b) =>
            b.name.toLowerCase().compareTo(a.name.toLowerCase()));
        break;
      case FolderSort.dateNewest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case FolderSort.dateOldest:
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case FolderSort.count:
        list.sort((a, b) =>
            (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0));
        break;
    }
    return list;
  }

  Widget _buildFoldersSectionHeader(BuildContext context, int total) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final foldersProvider = context.watch<FoldersProvider>();
    final selectionMode = foldersProvider.selectionMode;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(children: [
        Expanded(
          child: Text('${s.folders.toUpperCase()} ($total)',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: theme.colorScheme.onSurfaceVariant
                    .withValues(alpha: 0.6),
              )),
        ),
        Tooltip(
          message: s.selectItems,
          child: GestureDetector(
            onTap: total == 0
                ? null
                : () => context.read<FoldersProvider>().toggleSelectionMode(),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.checklist,
                  size: 15,
                  color: selectionMode
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ),
        GestureDetector(
          onTapDown: (d) => _showFolderSortMenu(context, d.globalPosition),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(Icons.sort, size: 15,
                color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ]),
    );
  }

  void _showFolderSortMenu(BuildContext context, Offset position) {
    final s = S.of(context);
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<FolderSort>(
      context: context,
      position: RelativeRect.fromRect(
          position & const Size(40, 40), Offset.zero & overlay.size),
      items: [
        CheckedPopupMenuItem(
            value: FolderSort.nameAz,
            checked: _folderSort == FolderSort.nameAz,
            child: Text('${s.title} A-Z')),
        CheckedPopupMenuItem(
            value: FolderSort.nameZa,
            checked: _folderSort == FolderSort.nameZa,
            child: Text('${s.title} Z-A')),
        CheckedPopupMenuItem(
            value: FolderSort.dateNewest,
            checked: _folderSort == FolderSort.dateNewest,
            child: Text('${s.created} ↓')),
        CheckedPopupMenuItem(
            value: FolderSort.dateOldest,
            checked: _folderSort == FolderSort.dateOldest,
            child: Text('${s.created} ↑')),
        CheckedPopupMenuItem(
            value: FolderSort.count,
            checked: _folderSort == FolderSort.count,
            child: Text(s.notesCount)),
      ],
    ).then((v) {
      if (v != null && mounted) setState(() => _folderSort = v);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final foldersProvider = context.watch<FoldersProvider>();
    final allFolders = foldersProvider.folders;
    final folders = _folderQuery.isEmpty
        ? allFolders
        : allFolders
            .where((f) =>
                f.name.toLowerCase().contains(_folderQuery.toLowerCase()))
            .toList();
    final noteCounts = foldersProvider.folderNoteCounts;
    final selectedFolderId = context.watch<NotesProvider>().selectedFolderId;
    final theme = Theme.of(context);

    final sortedFolders = _sortFolders(folders);
    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context),
          if (foldersProvider.selectionMode)
            _buildFolderSelectionBar(context, foldersProvider)
          else
            _buildSearchField(context),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: [
                _buildAllNotesItem(context, selectedFolderId == 'all'),
                _buildFoldersSectionHeader(context, allFolders.length),
                ...sortedFolders.map((f) => _buildFolderItem(
                      context,
                      f,
                      selected: selectedFolderId == f.id,
                      noteCount: noteCounts[f.id] ?? 0,
                      isEditing: _editingFolderId == f.id,
                    )),
                if (sortedFolders.isEmpty && _folderQuery.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(S.of(context).noNotesFound,
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant)),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          _buildTrashItem(context, selectedFolderId == 'trash'),
          _buildSettingsItem(context),
          _buildAboutItem(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final s = S.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              s.folders,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 18),
            tooltip: s.newNote,
            onPressed: () async {
              final notesProvider = context.read<NotesProvider>();
              final folderId = notesProvider.selectedFolderId;
              await notesProvider.createNote(
                  folderId: (folderId == 'all' || folderId == 'trash')
                      ? null
                      : folderId);
              widget.onNoteCreated?.call();
            },
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            iconSize: 18,
          ),
          IconButton(
            icon: const Icon(Icons.create_new_folder_outlined, size: 20),
            tooltip: s.createFolder,
            onPressed: _createFolder,
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            iconSize: 18,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: SizedBox(
        height: 34,
        child: TextField(
          controller: _searchController,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: '${S.of(context).folders}…',
            prefixIcon: const Icon(Icons.search, size: 16),
            suffixIcon: _folderQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 14),
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _folderQuery = '');
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
          onChanged: (v) => setState(() => _folderQuery = v),
        ),
      ),
    );
  }

  Widget _buildFolderSelectionBar(
      BuildContext context, FoldersProvider provider) {
    final s = S.of(context);
    final theme = Theme.of(context);
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
        IconButton(
          icon: Icon(Icons.delete_outline,
              size: 18, color: theme.colorScheme.error),
          tooltip: s.delete,
          visualDensity: VisualDensity.compact,
          onPressed: provider.selectedCount == 0
              ? null
              : () => _confirmDeleteSelectedFolders(context, provider),
        ),
      ]),
    );
  }

  void _confirmDeleteSelectedFolders(
      BuildContext context, FoldersProvider provider) {
    final s = S.of(context);
    bool moveToAll = true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('${s.delete} (${provider.selectedCount})'),
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
                  backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () async {
                await provider.deleteSelected(moveNotesToAllNotes: moveToAll);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  context.read<NotesProvider>().loadNotes(folderId: 'all');
                }
              },
              child: Text(s.delete),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsItem(BuildContext context) {
    return _buildSidebarItem(
      context: context,
      icon: Icons.settings_outlined,
      label: S.of(context).settings,
      selected: false,
      onTap: () {
        if (widget.onOpenSettings != null) {
          widget.onOpenSettings!();
        } else {
          widget.onNavigate?.call();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SettingsScreen()),
          );
        }
      },
    );
  }

  Widget _buildAboutItem(BuildContext context) {
    return _buildSidebarItem(
      context: context,
      icon: Icons.info_outline,
      label: S.of(context).about,
      selected: false,
      onTap: () {
        if (widget.onOpenAbout != null) {
          widget.onOpenAbout!();
        } else {
          widget.onNavigate?.call();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const AboutScreen()),
          );
        }
      },
    );
  }

  Widget _buildAllNotesItem(BuildContext context, bool selected) {
    final totalCount = context.watch<NotesProvider>().noteCount;
    return _buildSidebarItem(
      context: context,
      icon: Icons.notes,
      label: S.of(context).allNotes,
      suffix: '$totalCount',
      selected: selected,
      onTap: () {
        context
            .read<NotesProvider>()
            .loadNotes(folderId: 'all', clearSelection: true);
        widget.onNavigate?.call();
      },
    );
  }

  Widget _buildFolderItem(
    BuildContext context,
    Folder folder, {
    bool selected = false,
    int noteCount = 0,
    bool isEditing = false,
  }) {
    final foldersProvider = context.watch<FoldersProvider>();
    final selectionMode = foldersProvider.selectionMode;
    final checked = foldersProvider.isSelected(folder.id);
    final theme = Theme.of(context);
    return _buildSidebarItem(
      context: context,
      icon: Icons.folder_outlined,
      selectedIcon: Icons.folder,
      label: folder.name,
      subtitle: isEditing
          ? null
          : DateFormat.yMMMd(S.of(context).lang)
              .add_Hm()
              .format(folder.createdAt),
      suffix: selectionMode ? null : '$noteCount',
      selected: selected || checked,
      isEditing: isEditing,
      leading: selectionMode
          ? Icon(
              checked ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 18,
              color: checked
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            )
          : null,
      onCommitEdit: (newName) async {
        if (newName.trim().isNotEmpty && newName.trim() != folder.name) {
          await context.read<FoldersProvider>().renameFolder(folder, newName.trim());
        }
        setState(() => _editingFolderId = null);
      },
      onTap: () {
        if (selectionMode) {
          context.read<FoldersProvider>().toggleSelected(folder.id);
          return;
        }
        if (_editingFolderId != folder.id) {
          context
              .read<NotesProvider>()
              .loadNotes(folderId: folder.id, clearSelection: true);
          widget.onNavigate?.call();
        }
      },
      onDoubleTap: () {
        setState(() => _editingFolderId = folder.id);
      },
      onContextMenu: (pos) => _showFolderContextMenu(context, folder, pos),
    );
  }

  Widget _buildTrashItem(BuildContext context, bool selected) {
    final notesProvider = context.watch<NotesProvider>();
    final trashedNoteCount = notesProvider.trashedNoteCount;

    return _buildSidebarItem(
      context: context,
      icon: Icons.delete_outline,
      label: S.of(context).trash,
      suffix: trashedNoteCount > 0 ? '$trashedNoteCount' : null,
      selected: selected,
      onTap: () {
        notesProvider.selectNote(null);
        notesProvider.loadTrash();
        context.read<FoldersProvider>().loadTrash();
        widget.onNavigate?.call();
      },
    );
  }

  Widget _buildSidebarItem({
    required BuildContext context,
    required IconData icon,
    IconData? selectedIcon,
    required String label,
    String? subtitle,
    String? suffix,
    required bool selected,
    bool isEditing = false,
    void Function(String)? onCommitEdit,
    required VoidCallback onTap,
    VoidCallback? onDoubleTap,
    void Function(Offset)? onContextMenu,
    Widget? leading,
  }) {
    final theme = Theme.of(context);
    final bgColor = selected
        ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
        : Colors.transparent;
    final fgColor = selected
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    return GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onSecondaryTapDown:
          onContextMenu == null ? null : (d) => onContextMenu(d.globalPosition),
      onLongPressStart:
          onContextMenu == null ? null : (d) => onContextMenu(d.globalPosition),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          color: bgColor,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              if (leading != null) ...[leading, const SizedBox(width: 4)],
              Icon(
                selected ? (selectedIcon ?? icon) : icon,
                size: 18,
                color: fgColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: isEditing
                    ? _buildInlineEditor(context, label, onCommitEdit!)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 13,
                              color: fgColor,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 10,
                                color: fgColor.withValues(alpha: 0.55),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
              ),
              if (suffix != null && !isEditing) ...[
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    suffix,
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInlineEditor(
      BuildContext context, String initial, void Function(String) onCommit) {
    final controller = TextEditingController(text: initial);
    final focusNode = FocusNode();
    focusNode.requestFocus();
    controller.selection = TextSelection(
        baseOffset: 0, extentOffset: initial.length);

    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: true,
      decoration: const InputDecoration(
        border: InputBorder.none,
        isDense: true,
        contentPadding: EdgeInsets.zero,
      ),
      style: const TextStyle(fontSize: 13),
      onSubmitted: (v) => onCommit(v),
      onTapOutside: (_) => onCommit(controller.text),
    );
  }

  void _showFolderContextMenu(
      BuildContext context, Folder folder, Offset position) {
    final foldersProvider = context.read<FoldersProvider>();
    final notesProvider = context.read<NotesProvider>();
    final s = S.of(context);
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'rename',
          child: ListTile(
            leading: const Icon(Icons.edit, size: 20),
            title: Text(s.rename),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'select',
          child: ListTile(
            leading: const Icon(Icons.checklist, size: 20),
            title: Text(s.selectItems),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: ListTile(
            leading:
                const Icon(Icons.delete_outline, size: 20, color: Colors.red),
            title: Text(s.delete, style: const TextStyle(color: Colors.red)),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    ).then((value) {
      if (!mounted) return;
      if (value == 'rename') {
        setState(() => _editingFolderId = folder.id);
      } else if (value == 'select') {
        foldersProvider.enterSelection(folder.id);
      } else if (value == 'delete') {
        _confirmDeleteFolder(context, folder, foldersProvider, notesProvider);
      }
    });
  }

  void _createFolder() async {
    final foldersProvider = context.read<FoldersProvider>();
    final notesProvider = context.read<NotesProvider>();
    final folder = await foldersProvider.createFolder(S.read(context).newFolder);
    if (!mounted) return;
    setState(() => _editingFolderId = folder.id);
    notesProvider.selectNote(null);
    notesProvider.loadNotes(folderId: folder.id);
  }

  void _confirmDeleteFolder(
      BuildContext context,
      Folder folder,
      FoldersProvider foldersProvider,
      NotesProvider notesProvider) {
    _showDeleteFolderDialog(folder);
  }

  /// Delete-folder dialog with a "move notes to All Notes" checkbox (checked by
  /// default). When unchecked, the folder's notes are sent to Trash too.
  void _showDeleteFolderDialog(Folder folder) {
    final foldersProvider = context.read<FoldersProvider>();
    final notesProvider = context.read<NotesProvider>();
    final s = S.of(context);
    bool moveToAll = true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('${s.delete} — ${folder.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: moveToAll,
                onChanged: (v) => setLocal(() => moveToAll = v ?? true),
                title: Text(s.moveNotesToAllNotes,
                    style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                    moveToAll ? s.notesKeptInAllNotes : s.notesSentToTrash,
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () {
                foldersProvider.deleteFolder(folder,
                    moveNotesToAllNotes: moveToAll);
                notesProvider.loadNotes(folderId: 'all');
                Navigator.pop(ctx);
              },
              child: Text(s.delete),
            ),
          ],
        ),
      ),
    );
  }
}
