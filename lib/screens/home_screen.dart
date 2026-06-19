// Top-level adaptive shell. Chooses a desktop, tablet or mobile layout based on
// width and hosts the folder sidebar, notes list, and the right-hand pane
// (note editor, Settings, or About). Owns sidebar sizing and which pane shows.
import 'dart:io';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../models/note.dart';
import '../providers/notes_provider.dart';
import '../providers/folders_provider.dart';
import '../widgets/folder_sidebar.dart';
import '../widgets/notes_sidebar.dart';
import '../widgets/note_editor.dart';
import '../screens/settings_screen.dart';
import '../screens/about_screen.dart';
import '../l10n/strings.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  double _folderSidebarWidth = 220;
  double _notesSidebarWidth = 280;
  bool _folderSidebarVisible = true;
  bool _showSettings = false; // desktop: show settings in the right pane
  bool _showAbout = false; // desktop: show the About page in the right pane
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const double _minSidebarWidth = 160;
  static const double _maxFolderSidebarWidth = 400;
  static const double _maxNotesSidebarWidth = 500;
  static const double _dividerWidth = 4;

  NotesProvider? _notesProv;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final np = context.read<NotesProvider>();
    if (np != _notesProv) {
      _notesProv?.removeListener(_onNotesChanged);
      _notesProv = np;
      np.addListener(_onNotesChanged);
    }
  }

  // Close the desktop settings / about pane as soon as the user opens a note.
  void _onNotesChanged() {
    if ((_showSettings || _showAbout) && _notesProv?.selectedNote != null) {
      setState(() {
        _showSettings = false;
        _showAbout = false;
      });
    }
  }

  @override
  void dispose() {
    _notesProv?.removeListener(_onNotesChanged);
    super.dispose();
  }

  /// True on the desktop platforms that draw the custom in-app title bar.
  /// Mobile platforms (Android/iOS) instead get a Material [AppBar].
  ///
  /// Uses [defaultTargetPlatform] (rather than `dart:io`'s [Platform]) so the
  /// chrome is consistent with Flutter's platform model and can be exercised in
  /// widget tests via `debugDefaultTargetPlatformOverride`.
  bool get _isDesktopPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return true;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width < 600) {
      return _buildMobileLayout();
    } else if (width < 900) {
      return _buildTabletLayout();
    }
    return _buildDesktopLayout();
  }

  // ─── DESKTOP ───
  Widget _buildDesktopLayout() {
    final hasWindowBar = _isDesktopPlatform;

    return Scaffold(
      // SafeArea keeps the sidebars/editor clear of the status bar/notch on
      // large Android tablets (which reach this layout but have no title bar).
      // On desktop the safe-area insets are zero, so this is a no-op there.
      body: SafeArea(
        child: Column(
        children: [
          if (hasWindowBar) _buildCustomTitleBar(),
          Expanded(
            child: Row(
              children: [
                if (_folderSidebarVisible) ...[
                  SizedBox(
                    width: _folderSidebarWidth,
                    child: FolderSidebar(
                      onOpenSettings: () => setState(() {
                        _showSettings = true;
                        _showAbout = false;
                      }),
                      onOpenAbout: () => setState(() {
                        _showAbout = true;
                        _showSettings = false;
                      }),
                    ),
                  ),
                  _buildResizeHandle(
                    onDrag: (delta) {
                      setState(() {
                        _folderSidebarWidth = (_folderSidebarWidth + delta)
                            .clamp(_minSidebarWidth, _maxFolderSidebarWidth);
                      });
                    },
                  ),
                ],
                SizedBox(
                  width: _notesSidebarWidth,
                  child: const NotesSidebar(),
                ),
                _buildResizeHandle(
                  onDrag: (delta) {
                    setState(() {
                      _notesSidebarWidth = (_notesSidebarWidth + delta)
                          .clamp(_minSidebarWidth, _maxNotesSidebarWidth);
                    });
                  },
                ),
                Expanded(child: _mainPane()),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  /// The right pane on desktop/tablet: settings, About, or the note editor.
  Widget _mainPane() {
    if (_showSettings) {
      return SettingsScreen(
          onClose: () => setState(() => _showSettings = false));
    }
    if (_showAbout) {
      return AboutScreen(onClose: () => setState(() => _showAbout = false));
    }
    return const NoteEditor();
  }

  Widget _buildCustomTitleBar() {
    final theme = Theme.of(context);
    final s = S.of(context);

    return Container(
      height: 38,
      // Reserve space for the macOS traffic-light buttons, which overlay the
      // top-left corner because the window uses a full-size content view. On
      // Windows/Linux the min/max/close controls live in the native title bar
      // above this strip, so no left reservation is needed there.
      padding: EdgeInsets.only(left: Platform.isMacOS ? 78 : 12),
      color: theme.colorScheme.surfaceContainerLowest,
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              _folderSidebarVisible ? Icons.menu_open : Icons.menu,
              size: 16,
            ),
            tooltip: _folderSidebarVisible ? s.folders : s.folders,
            onPressed: () =>
                setState(() => _folderSidebarVisible = !_folderSidebarVisible),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            iconSize: 16,
          ),
          const Spacer(),
          Text(
            _sectionTitle(context),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () {
              final notesProvider = context.read<NotesProvider>();
              final folderId = notesProvider.selectedFolderId;
              notesProvider.createNote(
                  folderId: folderId == 'all' || folderId == 'trash'
                      ? null
                      : folderId);
            },
            icon: const Icon(Icons.add, size: 14),
            label: Text(s.newNote, style: const TextStyle(fontSize: 11)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 18),
            tooltip: s.settings,
            onPressed: () => _openSettings(context),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            iconSize: 16,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline, size: 18),
            tooltip: s.about,
            onPressed: () => _openAbout(context),
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            iconSize: 16,
          ),
          const SizedBox(width: 14),
        ],
      ),
    );
  }

  Widget _buildResizeHandle({required void Function(double) onDrag}) {
    return GestureDetector(
      onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Container(
          width: _dividerWidth,
          color: Colors.transparent,
        ),
      ),
    );
  }

  /// The window/title-bar text: the current section name (folder, All Notes,
  /// or Trash) rather than a note preview snippet.
  String _sectionTitle(BuildContext context) {
    final s = S.of(context);
    final folderId = context.watch<NotesProvider>().selectedFolderId;
    if (folderId == 'trash') return s.trash;
    if (folderId == 'all') return s.allNotes;
    final folder = context
        .watch<FoldersProvider>()
        .folders
        .where((f) => f.id == folderId)
        .firstOrNull;
    return folder?.name ?? s.appName;
  }

  void _openSettings(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 600) {
      // Desktop / tablet: show in the right pane, keeping the sidebars.
      setState(() {
        _showSettings = true;
        _showAbout = false;
      });
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsScreen()),
      );
    }
  }

  void _openAbout(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    if (width >= 600) {
      // Desktop / tablet: show in the right pane, keeping the sidebars.
      setState(() {
        _showAbout = true;
        _showSettings = false;
      });
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const AboutScreen()),
      );
    }
  }

  /// Push the full-screen note editor (mobile). The editor auto-focuses the
  /// writing area when it opens onto a freshly created note.
  void _openMobileEditor() {
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => _MobileEditorScreen(
                onBack: () => Navigator.of(context).pop(),
              )),
    );
  }

  // ─── TABLET (split: notes list + editor, 600–900px) ───
  Widget _buildTabletLayout() {
    final isDesktop = _isDesktopPlatform;
    final s = S.of(context);

    return Scaffold(
      key: _scaffoldKey,
      // Desktop platforms use the custom in-window title bar; mobile platforms
      // (where this layout is reached in landscape / on small tablets) need a
      // real AppBar so the folder drawer, "new note" and settings are reachable
      // and the content sits below the status bar.
      appBar: isDesktop
          ? null
          : AppBar(
              titleSpacing: 0,
              title: Text(_sectionTitle(context),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 18)),
              leading: IconButton(
                icon: const Icon(Icons.menu),
                tooltip: s.folders,
                onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: s.newNote,
                  onPressed: () {
                    final fid =
                        context.read<NotesProvider>().selectedFolderId;
                    context.read<NotesProvider>().createNote(
                        folderId:
                            (fid == 'all' || fid == 'trash') ? null : fid);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: s.settings,
                  onPressed: () => _openSettings(context),
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: s.about,
                  onPressed: () => _openAbout(context),
                ),
              ],
            ),
      body: SafeArea(
        // On mobile the AppBar already clears the status bar, so only guard the
        // sides/bottom there; on desktop the custom title bar must reach the top.
        top: isDesktop,
        child: Column(
          children: [
            if (isDesktop) _buildCustomTitleBar(),
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: _notesSidebarWidth,
                    child: const NotesSidebar(),
                  ),
                  _buildResizeHandle(
                    onDrag: (delta) {
                      setState(() {
                        _notesSidebarWidth = (_notesSidebarWidth + delta)
                            .clamp(_minSidebarWidth, _maxNotesSidebarWidth);
                      });
                    },
                  ),
                  Expanded(child: _mainPane()),
                ],
              ),
            ),
          ],
        ),
      ),
      drawer: Drawer(
        child: FolderSidebar(
          onNavigate: () => Navigator.of(context).maybePop(),
          // Tablet shows the editor in the right pane, so just close the drawer.
          onNoteCreated: () => Navigator.of(context).maybePop(),
          onOpenSettings: () {
            Navigator.of(context).maybePop();
            setState(() {
              _showSettings = true;
              _showAbout = false;
            });
          },
          onOpenAbout: () {
            Navigator.of(context).maybePop();
            setState(() {
              _showAbout = true;
              _showSettings = false;
            });
          },
        ),
      ),
    );
  }

  // ─── MOBILE ───
  Widget _buildMobileLayout() {
    final provider = context.watch<NotesProvider>();

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(
            _sectionTitle(context),
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () {
              final fid = provider.selectedFolderId;
              context.read<NotesProvider>().createNote(
                  folderId: (fid == 'all' || fid == 'trash') ? null : fid);
              _openMobileEditor();
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _openSettings(context),
          ),
        ],
      ),
      drawer: _buildMobileDrawer(),
      // Widen the edge zone so a swipe in from the left edge reliably opens the
      // folder drawer (Scaffold handles the left-edge drag gesture natively).
      drawerEdgeDragWidth: 60,
      body: NotesSidebar(
        mobileMode: true,
        onNoteTap: (note) => _openMobileEditor(),
        onNoteCreated: _openMobileEditor,
      ),
    );
  }

  Widget _buildMobileDrawer() {
    return Drawer(
      width: 280,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Bello Notes',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FolderSidebar(
                onNavigate: () {
                  Navigator.of(context).pop();
                },
                onNoteCreated: () {
                  // Close the drawer, then open the editor on the new note.
                  Navigator.of(context).pop();
                  _openMobileEditor();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Mobile Editor Screen ───
class _MobileEditorScreen extends StatelessWidget {
  final VoidCallback onBack;

  const _MobileEditorScreen({required this.onBack});

  @override
  Widget build(BuildContext context) {
    final note = context.watch<NotesProvider>().selectedNote;
    final s = S.of(context);
    final titleText =
        (note != null && note.displayTitle.isNotEmpty) ? note.displayTitle : s.newNote;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: onBack,
        ),
        title: Text(titleText,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 16)),
        actions: [
          if (note != null) ...[
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_horiz, size: 22),
              onSelected: (value) {
                switch (value) {
                  case 'pin':
                    context.read<NotesProvider>().togglePin(note);
                    break;
                  case 'move':
                    _showMobileMoveDialog(context, note);
                    break;
                  case 'delete':
                    context.read<NotesProvider>().deleteNote(note);
                    onBack();
                    break;
                  case 'export':
                    _showMobileExportDialog(context, note);
                    break;
                }
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'pin',
                  child: Row(
                    children: [
                      Icon(
                          note.isPinned
                              ? Icons.push_pin
                              : Icons.push_pin_outlined,
                          size: 20),
                      const SizedBox(width: 8),
                      Text(note.isPinned ? 'Unpin' : 'Pin'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'move',
                  child: Row(children: [
                    Icon(Icons.drive_file_move_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('Move to Folder'),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline, size: 20, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Delete', style: TextStyle(color: Colors.red)),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'export',
                  child: Row(children: [
                    Icon(Icons.share_outlined, size: 20),
                    SizedBox(width: 8),
                    Text('Export'),
                  ]),
                ),
              ],
            ),
          ],
        ],
      ),
      body: const NoteEditor(mobileMode: true),
    );
  }

  void _showMobileMoveDialog(BuildContext context, Note note) {
    final folders = context.read<FoldersProvider>().folders;
    final selected = Set<String>.from(note.folderIds);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const Text('Assign to Folders',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  FilledButton(
                      onPressed: () {
                        context.read<NotesProvider>().moveNoteToFolder(
                            note, selected.toList());
                        context.read<FoldersProvider>().refreshCounts();
                        Navigator.pop(ctx);
                      },
                      child: const Text('Done')),
                ]),
              ),
              ...folders.map((f) => CheckboxListTile(
                    title: Text(f.name),
                    value: selected.contains(f.id),
                    onChanged: (v) {
                      setDialogState(() {
                        if (v == true) {
                          selected.add(f.id);
                        } else {
                          selected.remove(f.id);
                        }
                      });
                    },
                  )),
            ],
          ),
        ),
      ),
    );
  }

  void _showMobileExportDialog(BuildContext context, Note note) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Export Note',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            ListTile(
              leading: const Icon(Icons.text_snippet),
              title: const Text('Export as .txt'),
              onTap: () {
                Navigator.pop(ctx);
                _exportNoteMobile(context, note, 'txt');
              },
            ),
            ListTile(
              leading: const Icon(Icons.code),
              title: const Text('Export as .md'),
              onTap: () {
                Navigator.pop(ctx);
                _exportNoteMobile(context, note, 'md');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportNoteMobile(
      BuildContext context, Note note, String ext) async {
    try {
      final name = note.title.isNotEmpty
          ? note.title.replaceAll(RegExp(r'[^\w\s]'), '_').trim()
          : 'note';
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Note',
        fileName: '$name.$ext',
        allowedExtensions: [ext],
        type: FileType.custom,
      );
      if (savePath == null) return;
      final text = note.plainText.isNotEmpty ? note.plainText : note.content;
      await File(savePath).writeAsString(text);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Exported to $savePath'),
              duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Export failed: $e'),
              duration: const Duration(seconds: 2)),
        );
      }
    }
  }
}
