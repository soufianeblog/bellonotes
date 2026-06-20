// The rich-text note editor. Wraps a flutter_quill editor with a custom
// formatting toolbar, title field, and embedded table/image builders, and
// keeps the note's Delta JSON content saved through [NotesProvider]. This is
// the largest widget in the app; sections are marked with banner comments.
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/src/packages/quill_markdown/delta_to_markdown.dart';
import 'package:flutter_quill/src/delta/delta_x.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/note.dart';
import '../providers/notes_provider.dart';
import '../providers/folders_provider.dart';
import '../providers/app_settings.dart';
import '../services/error_logger.dart';
import '../services/quill_html.dart';
import '../platform/platform_bridge.dart' as platform;
import '../l10n/strings.dart';

/// Identity record used so the editor only rebuilds when something meaningful
/// about the selected note changes — not on every debounced content save.
class _EditorSel {
  final String? id;
  final bool isTrash;
  final bool isDeleted;
  final bool isPinned;
  const _EditorSel(this.id, this.isTrash, this.isDeleted, this.isPinned);

  @override
  bool operator ==(Object other) =>
      other is _EditorSel &&
      other.id == id &&
      other.isTrash == isTrash &&
      other.isDeleted == isDeleted &&
      other.isPinned == isPinned;

  @override
  int get hashCode => Object.hash(id, isTrash, isDeleted, isPinned);
}

class NoteEditor extends StatefulWidget {
  final bool mobileMode;

  const NoteEditor({super.key, this.mobileMode = false});

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> with WidgetsBindingObserver {
  late QuillController _quillController;
  final TextEditingController _sourceController = TextEditingController();
  final FocusNode _editorFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _editorKey = GlobalKey();

  String? _lastNoteId;
  Note? _loadedNote;
  bool _suppressChanges = false;
  bool _htmlMode = false; // source toggle: rendered ⇄ raw HTML
  String _lastContent = '';
  Timer? _saveDebounce;
  OverlayEntry? _overlay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _quillController = QuillController.basic();
    _quillController.addListener(_onQuillChanged);
  }

  @override
  void dispose() {
    _flushSave();
    _removeOverlay();
    WidgetsBinding.instance.removeObserver(this);
    _quillController.removeListener(_onQuillChanged);
    _quillController.dispose();
    _sourceController.dispose();
    _editorFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Flush pending edits when the app loses focus / is backgrounded so nothing
  // is lost (TODO item: "when app loses focus").
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _flushSave();
    }
  }

  // ─── SAVING ───

  void _onQuillChanged() {
    if (_suppressChanges || _htmlMode) return;
    final deltaJson = jsonEncode(_quillController.document.toDelta().toJson());
    if (deltaJson != _lastContent) {
      _lastContent = deltaJson;
      _scheduleSave(deltaJson);
    }
    // Refresh toolbar active-state indicators (cheap, local).
    if (mounted) setState(() {});
  }

  void _scheduleSave(String content) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 500), () {
      _commitSave(content);
    });
  }

  void _commitSave(String content) {
    if (!mounted) return;
    // Always target the note currently loaded in the editor (not whatever is
    // selected now) so pending edits land on the right note during switches.
    final note = _loadedNote;
    if (note != null && content != note.content) {
      context.read<NotesProvider>().updateNoteContent(note, content);
    }
  }

  void _flushSave() {
    if (_saveDebounce?.isActive ?? false) {
      _saveDebounce!.cancel();
    }
    if (!mounted) return;
    if (_htmlMode) {
      _commitSave(_sourceController.text);
    } else {
      final deltaJson =
          jsonEncode(_quillController.document.toDelta().toJson());
      if (deltaJson != _lastContent) _lastContent = deltaJson;
      _commitSave(deltaJson);
    }
  }

  // ─── LOADING ───

  void _loadNoteContent(Note note, AppSettings settings) {
    if (note.id == _lastNoteId) return;
    // Switching notes: persist anything pending on the previous note first.
    _flushSave();
    _lastNoteId = note.id;
    _loadedNote = note;
    _suppressChanges = true;
    _htmlMode = false; // always reset to visual on note switch

    final isDelta = note.content.isNotEmpty && _isDeltaJson(note.content);

    if (isDelta) {
      try {
        _quillController.document =
            Document.fromJson(jsonDecode(note.content) as List);
      } catch (e, s) {
        ErrorLogger.instance
            .error('Failed to load note delta', details: '$e\n$s');
        _quillController.document = Document();
      }
    } else if (note.content.isNotEmpty) {
      try {
        final delta = DeltaX.fromMarkdown(note.content);
        _quillController.document = Document.fromDelta(delta);
      } catch (_) {
        _quillController.document = Document()..insert(0, note.content);
      }
    } else {
      _quillController.document = Document();
      _applyDefaultFormat(settings);
    }

    _lastContent = jsonEncode(_quillController.document.toDelta().toJson());
    _quillController.updateSelection(
        const TextSelection.collapsed(offset: 0), ChangeSource.local);

    _suppressChanges = false;

    // Auto-focus the writing area when this note was just created from a "new
    // note" button, so the user can start typing immediately. The provider
    // hands the id over exactly once.
    final justCreated =
        context.read<NotesProvider>().consumeJustCreatedNoteId() == note.id;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _highlightSearchInEditor();
      if (justCreated) _editorFocusNode.requestFocus();
    });
  }

  void _applyDefaultFormat(AppSettings settings) {
    Attribute? attr;
    switch (settings.defaultFormat) {
      case 'title':
        attr = Attribute.h1;
        break;
      case 'heading':
        attr = Attribute.h2;
        break;
      case 'subheading':
        attr = Attribute.h3;
        break;
      default:
        attr = null;
    }
    if (attr != null) {
      _quillController.formatText(0, 0, attr);
    }
  }

  bool _isDeltaJson(String content) {
    try {
      return jsonDecode(content) is List;
    } catch (_) {
      return false;
    }
  }

  void _highlightSearchInEditor() {
    final query = context.read<NotesProvider>().searchQuery;
    if (query.isEmpty) return;
    final plain = _quillController.document.toPlainText().toLowerCase();
    final idx = plain.indexOf(query.toLowerCase());
    if (idx == -1) return;
    _quillController.updateSelection(
        TextSelection(baseOffset: idx, extentOffset: idx + query.length),
        ChangeSource.local);
  }

  // ─── BUILD ───

  @override
  Widget build(BuildContext context) {
    return Selector<NotesProvider, _EditorSel>(
      selector: (_, p) => _EditorSel(p.selectedNote?.id, p.isTrashView,
          p.selectedNote?.isDeleted ?? false, p.selectedNote?.isPinned ?? false),
      builder: (context, sel, _) {
        final provider = context.read<NotesProvider>();
        final note = provider.selectedNote;
        final settings = context.read<AppSettings>();

        if (note == null) return _buildEmptyState(context);
        if (provider.isTrashView && note.isDeleted) {
          return _buildTrashedNoteView(context, note);
        }

        _loadNoteContent(note, settings);
        // Keep the loaded reference fresh (e.g. after a pin toggle) so saves
        // copyWith from the latest note state, not a stale instance.
        _loadedNote = note;

        return Column(
          children: [
            _buildToolbar(context, note),
            _buildMetaBar(context, note),
            Expanded(child: _buildEditor(context, note)),
            _buildStatusBar(context, note),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final s = S.of(context);
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.edit_note,
            size: 64,
            color: Theme.of(context)
                .colorScheme
                .onSurfaceVariant
                .withValues(alpha: 0.3)),
        const SizedBox(height: 16),
        Text(s.selectOrCreate,
            style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => context.read<NotesProvider>().createNote(),
          icon: const Icon(Icons.add, size: 18),
          label: Text(s.newNote),
        ),
      ]),
    );
  }

  Widget _buildTrashedNoteView(BuildContext context, Note note) {
    final s = S.of(context);
    final readOnlyController = QuillController(
      document: _parseDocument(note.content),
      selection: const TextSelection.collapsed(offset: 0),
      readOnly: true,
    );
    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
        color: Theme.of(context)
            .colorScheme
            .errorContainer
            .withValues(alpha: 0.3),
        child: Row(children: [
          const Icon(Icons.delete_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text('${s.trash} — ${s.restore}?',
                style: const TextStyle(fontSize: 13)),
          ),
          TextButton.icon(
            onPressed: () =>
                context.read<NotesProvider>().restoreNote(note.id),
            icon: const Icon(Icons.restore, size: 16),
            label: Text(s.restore),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => _confirmPermanentDelete(context, note),
            icon: const Icon(Icons.delete_forever, size: 16),
            label: Text(s.deleteForever),
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
          ),
        ]),
      ),
      Expanded(
        child: QuillEditor.basic(
          controller: readOnlyController,
          config: QuillEditorConfig(
            showCursor: false,
            padding: const EdgeInsets.all(24),
            embedBuilders: [
              _ImageEmbedBuilder(),
              _TableEmbedBuilder(),
            ],
          ),
        ),
      ),
    ]);
  }

  Document _parseDocument(String content) {
    if (content.isEmpty) return Document();
    try {
      final decoded = jsonDecode(content);
      if (decoded is List) return Document.fromJson(decoded);
    } catch (_) {}
    return Document()..insert(0, content);
  }

  void _doDelete(BuildContext context, Note note) {
    context.read<NotesProvider>().deleteNote(note);
    context.read<FoldersProvider>().refreshCounts();
  }

  void _refocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_editorFocusNode.hasFocus) {
        _editorFocusNode.requestFocus();
      }
    });
  }

  // ─── UNIFIED RESPONSIVE TOOLBAR (wraps to 2nd row when needed) ───

  Widget _buildToolbar(BuildContext context, Note note) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final disabled = _htmlMode;

    // NOTE: We intentionally do NOT wrap the toolbar in a focus barrier — the
    // editable font/size fields need to be focusable. Tappable buttons use
    // `canRequestFocus: false` so they never steal the editor's selection.
    return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: theme.colorScheme.surface,
        child: Wrap(
          spacing: 2,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // Paragraph style as a single labeled dropdown.
            _buildStyleDropdown(context, enabled: !disabled),
            _divider(),
            _buildFontField(context, enabled: !disabled),
            _buildSizeField(context, enabled: !disabled),
            _divider(),
            // Inline formatting (disabled in HTML source mode).
            _tBtn(Icons.format_bold, s.bold, () => _qfmt(Attribute.bold),
                active: !disabled && _hasInlineStyle(Attribute.bold),
                enabled: !disabled),
            _tBtn(Icons.format_italic, s.italic,
                () => _qfmt(Attribute.italic),
                active: !disabled && _hasInlineStyle(Attribute.italic),
                enabled: !disabled),
            _tBtn(Icons.format_underlined, s.underline,
                () => _qfmt(Attribute.underline),
                active: !disabled && _hasInlineStyle(Attribute.underline),
                enabled: !disabled),
            _tBtn(Icons.format_strikethrough, s.strike,
                () => _qfmt(Attribute.strikeThrough),
                active: !disabled && _hasInlineStyle(Attribute.strikeThrough),
                enabled: !disabled),
            _tBtn(Icons.format_color_text, s.textColor,
                () => _showColorPicker(context, background: false),
                enabled: !disabled),
            _tBtn(Icons.border_color, s.highlight,
                () => _showColorPicker(context, background: true),
                enabled: !disabled),
            _divider(),
            // Alignment.
            _tBtn(Icons.format_align_left, s.alignLeft,
                () => _applyAlign(null),
                active: !disabled && _isAlign(null), enabled: !disabled),
            _tBtn(Icons.format_align_center, s.alignCenter,
                () => _applyAlign('center'),
                active: !disabled && _isAlign('center'), enabled: !disabled),
            _tBtn(Icons.format_align_right, s.alignRight,
                () => _applyAlign('right'),
                active: !disabled && _isAlign('right'), enabled: !disabled),
            _tBtn(Icons.format_align_justify, s.alignJustify,
                () => _applyAlign('justify'),
                active: !disabled && _isAlign('justify'), enabled: !disabled),
            _divider(),
            _tBtn(Icons.format_list_bulleted, s.bullets,
                () => _qfmt(Attribute.ul),
                active: !disabled && _hasBlockStyle(Attribute.ul),
                enabled: !disabled),
            _tBtn(Icons.format_list_numbered, s.numbered,
                () => _qfmt(Attribute.ol),
                active: !disabled && _hasBlockStyle(Attribute.ol),
                enabled: !disabled),
            _tBtn(Icons.checklist, s.checklist, _toggleChecklist,
                active: !disabled && _hasBlockStyle(Attribute.unchecked),
                enabled: !disabled),
            _tBtn(Icons.format_quote, s.quote,
                () => _qfmt(Attribute.blockQuote),
                active: !disabled && _hasBlockStyle(Attribute.blockQuote),
                enabled: !disabled),
            _tBtn(Icons.code, s.codeBlock, () => _qfmt(Attribute.codeBlock),
                active: !disabled && _hasBlockStyle(Attribute.codeBlock),
                enabled: !disabled),
            _divider(),
            _tBtn(Icons.table_chart_outlined, s.table,
                () => _showTableGridPicker(context),
                enabled: !disabled),
            _tBtn(Icons.image_outlined, s.photo, () => _attachPhoto(context),
                enabled: !disabled),
            _tBtn(Icons.link, s.link, () => _showInlineLinkEditor(context),
                enabled: !disabled),
            _divider(),
            _tBtn(_htmlMode ? Icons.visibility : Icons.code,
                _htmlMode ? s.visual : 'HTML', _toggleHtmlMode,
                active: _htmlMode),
            _tBtn(
                context.watch<AppSettings>().darkEditorBg
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                s.darkEditorBg, () {
              final settings = context.read<AppSettings>();
              settings.setDarkEditorBg(!settings.darkEditorBg);
            }, active: context.watch<AppSettings>().darkEditorBg),
            _divider(),
            _tBtn(note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                note.isPinned ? s.unpin : s.pin, () {
              context.read<NotesProvider>().togglePin(note);
              _refocus();
            }, active: note.isPinned),
            _tBtn(Icons.folder_copy_outlined, s.move,
                () => _showMoveDialog(context, note)),
            _tBtn(Icons.share_outlined, s.export,
                () => _exportNoteWithPicker(context, note)),
            _tBtn(Icons.delete_outline, s.delete,
                () => _doDelete(context, note)),
          ],
        ),
      );
  }

  Widget _tBtn(IconData icon, String label, VoidCallback onTap,
      {bool active = false, bool enabled = true}) {
    final theme = Theme.of(context);
    final color = !enabled
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)
        : active
            ? theme.colorScheme.primary
            : theme.colorScheme.onSurfaceVariant;
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        canRequestFocus: false,
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: active
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: color),
          ]),
        ),
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 18,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
      );

  // ─── STYLE / FONT / SIZE DROPDOWNS ───

  static const _fonts = [
    'Arial', 'Helvetica', 'Sans Serif', 'Serif', 'Monospace',
    'Georgia', 'Times New Roman', 'Courier New', 'Verdana', 'Trebuchet MS',
    'Comic Sans MS', 'Tahoma', 'Garamond', 'Roboto',
  ];
  static const _sizes = ['12', '14', '16', '18', '20', '24', '28', '32', '48'];

  Widget _pillButton(String label, VoidCallback? onTap,
      {IconData? trailing, bool enabled = true}) {
    final theme = Theme.of(context);
    return InkWell(
      canRequestFocus: false,
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: enabled
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.3))),
          Icon(trailing ?? Icons.arrow_drop_down,
              size: 16,
              color: enabled
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
        ]),
      ),
    );
  }

  String _currentStyleLabel(S s) {
    if (_hasBlockStyle(Attribute.h1)) return s.title;
    if (_hasBlockStyle(Attribute.h2)) return s.heading;
    if (_hasBlockStyle(Attribute.h3)) return '${s.heading} 3';
    return s.body;
  }

  Widget _buildStyleDropdown(BuildContext context, {required bool enabled}) {
    final s = S.of(context);
    return PopupMenuButton<String>(
      enabled: enabled,
      tooltip: '',
      offset: const Offset(0, 32),
      onSelected: (v) {
        switch (v) {
          case 'body':
            _setBody();
            break;
          case 'h1':
            _setBlock(Attribute.h1);
            break;
          case 'h2':
            _setBlock(Attribute.h2);
            break;
          case 'h3':
            _setBlock(Attribute.h3);
            break;
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem(value: 'body', child: Text(s.body)),
        PopupMenuItem(
            value: 'h1',
            child: Text(s.title,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold))),
        PopupMenuItem(
            value: 'h2',
            child: Text(s.heading,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600))),
        PopupMenuItem(
            value: 'h3',
            child: Text('${s.heading} 3',
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600))),
      ],
      child: _pillButton(enabled ? _currentStyleLabel(s) : s.body, null,
          enabled: enabled),
    );
  }

  /// The current inline attribute value at the caret/selection (e.g. the
  /// active font family or font size), or null when none is applied.
  String? _inlineValue(String key) {
    final sel = _quillController.selection;
    if (!sel.isValid) return null;
    final offset = sel.start;
    final checkOffset = sel.isCollapsed && offset > 0 ? offset - 1 : offset;
    final len = sel.isCollapsed ? 0 : sel.end - sel.start;
    final style = _quillController.document.collectStyle(
        checkOffset.clamp(0, _quillController.document.length - 1),
        len.clamp(0, _quillController.document.length));
    return style.attributes[key]?.value?.toString();
  }

  /// Editable font field: shows the active font, lets you type one (with the
  /// list filtered as you type), and the dropdown opens the searchable picker.
  Widget _buildFontField(BuildContext context, {required bool enabled}) {
    // No "Default" pseudo-font: the effective base font is Arial.
    final current = _inlineValue('font') ?? 'Arial';
    return _ToolbarComboField(
      value: current,
      width: 124,
      enabled: enabled,
      hint: S.of(context).font,
      presets: _fonts,
      onDropdownTap: enabled ? () => _showFontPicker(context) : null,
      onSubmit: (v) {
        final t = v.trim();
        _applyInline('font', t.isEmpty ? null : t);
      },
    );
  }

  /// Editable font-size field: shows the active size, lets you type a custom
  /// value, and the dropdown lists the presets.
  Widget _buildSizeField(BuildContext context, {required bool enabled}) {
    final current = _inlineValue('size') ?? '';
    return _ToolbarComboField(
      value: current,
      width: 66,
      enabled: enabled,
      hint: S.of(context).size,
      keyboardType: TextInputType.number,
      presets: _sizes,
      onSubmit: (v) {
        final t = v.trim();
        _applyInline('size', t.isEmpty ? null : t);
      },
    );
  }

  void _showFontPicker(BuildContext context) {
    final s = S.of(context);
    final query = ValueNotifier<String>('');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.font),
        content: SizedBox(
          width: 320,
          height: 420,
          child: Column(children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: s.font,
                  border: const OutlineInputBorder()),
              onChanged: (v) => query.value = v.toLowerCase(),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: query,
                builder: (_, q, _) {
                  final list = _fonts
                      .where((f) => f.toLowerCase().contains(q))
                      .toList();
                  return ListView.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      final f = list[i];
                      return ListTile(
                        dense: true,
                        title: Text(f, style: TextStyle(fontFamily: f)),
                        onTap: () {
                          Navigator.pop(ctx);
                          _applyInline('font', f);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showColorPicker(BuildContext context, {required bool background}) {
    final s = S.of(context);
    const palette = [
      '#000000', '#5f6368', '#9aa0a6', '#ffffff',
      '#d93025', '#e8710a', '#f9ab00', '#188038',
      '#1a73e8', '#7b1fa2', '#c2185b', '#795548',
      '#f28b82', '#fdd663', '#a8dab5', '#aecbfa',
    ];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(background ? s.highlight : s.textColor),
        content: SizedBox(
          width: 280,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final hex in palette)
                InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    _applyInline(background ? 'background' : 'color', hex);
                  },
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Color(int.parse('FF${hex.substring(1)}', radix: 16)),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .outlineVariant
                              .withValues(alpha: 0.6)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _applyInline(background ? 'background' : 'color', null);
            },
            child: Text(s.noColor),
          ),
        ],
      ),
    );
  }

  void _applyInline(String key, String? value) {
    _quillController.formatSelection(
        Attribute(key, AttributeScope.inline, value));
    _refocus();
    if (mounted) setState(() {});
  }

  void _applyAlign(String? value) {
    _quillController.formatSelection(
        Attribute('align', AttributeScope.block, value));
    _refocus();
    if (mounted) setState(() {});
  }

  bool _isAlign(String? value) {
    final sel = _quillController.selection;
    final index = sel.isValid ? sel.start : 0;
    final style = _quillController.document.collectStyle(
        index.clamp(0, _quillController.document.length - 1), 0);
    final found = style.attributes['align'];
    if (value == null) return found == null;
    return found?.value == value;
  }

  void _setBlock(Attribute attr) {
    _quillController.formatSelection(attr);
    _refocus();
    if (mounted) setState(() {});
  }

  // ─── FORMATTING ACTIONS ───

  void _toggleChecklist() {
    final sel = _quillController.selection;
    if (_hasBlockStyle(Attribute.unchecked) ||
        _hasBlockStyle(Attribute.checked)) {
      _quillController.formatSelection(Attribute.clone(Attribute.unchecked, null));
    } else if (sel.isValid) {
      _quillController.formatSelection(Attribute.unchecked);
    }
    _refocus();
    if (mounted) setState(() {});
  }

  /// Google-Docs–style size picker: drag/hover a grid to choose dimensions.
  void _showTableGridPicker(BuildContext context) async {
    final res = await showDialog<List<int>>(
      context: context,
      builder: (ctx) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: _TableSizePicker(),
        ),
      ),
    );
    if (res != null) _insertTable(res[0], res[1]);
  }

  void _insertTable([int rows = 3, int cols = 2]) {
    final data = jsonEncode({
      'rows': List.generate(
        rows,
        (r) => List.generate(
            cols, (c) => r == 0 ? 'Column ${c + 1}' : ''),
      ),
    });
    _insertEmbedBlock(BlockEmbed('table', data));
  }

  /// Inserts a block embed (image/table) isolated on its own line, followed by
  /// an empty paragraph. Keeping embeds on their own line avoids the oversized
  /// caret Quill otherwise draws next to a tall embed.
  void _insertEmbedBlock(BlockEmbed embed) {
    final doc = _quillController.document;
    final sel = _quillController.selection;
    var index =
        (sel.isValid ? sel.baseOffset : doc.length - 1).clamp(0, doc.length - 1);
    final plain = doc.toPlainText();
    if (index > 0 && index <= plain.length && plain[index - 1] != '\n') {
      _quillController.replaceText(index, 0, '\n', null);
      index += 1;
    }
    _quillController.replaceText(index, 0, embed, null);
    _quillController.replaceText(index + 1, 0, '\n', null);
    _quillController.updateSelection(
        TextSelection.collapsed(offset: index + 2), ChangeSource.local);
    _refocus();
  }

  /// Whether [docOffset] still points at an editable embed leaf.
  ///
  /// A resize/edit gesture on an embed can finish *after* the document has
  /// changed beneath it (e.g. autosave reformatting or an edit above the
  /// embed), leaving the offset captured by the embed builder stale. A Quill
  /// document always ends with a mandatory newline terminator, so a real embed
  /// can never sit at `length - 1`; replacing there (or past it) trips a hard
  /// assertion deep inside flutter_quill's `QuillContainer.insert`. Guarding
  /// the range turns that crash into a harmless no-op without rejecting any
  /// legitimate offset.
  bool _embedOffsetIsValid(int docOffset) =>
      docOffset >= 0 && docOffset < _quillController.document.length - 1;

  /// Replaces the table embed at [docOffset] with updated row data.
  void _updateTable(int docOffset, String newJson) {
    if (!_embedOffsetIsValid(docOffset)) return;
    _quillController.replaceText(
        docOffset, 1, BlockEmbed('table', newJson), null);
  }

  /// Replaces an image embed at [docOffset] with updated data (width/link).
  void _updateImage(int docOffset, String newData) {
    if (!_embedOffsetIsValid(docOffset)) return;
    _quillController.replaceText(
        docOffset, 1, BlockEmbed.image(newData), null);
    _refocus();
  }

  /// Removes the embed (image/table) at [docOffset].
  void _removeEmbed(int docOffset) {
    if (!_embedOffsetIsValid(docOffset)) return;
    _quillController.replaceText(docOffset, 1, '', null);
    _refocus();
    if (mounted) setState(() {});
  }

  void _setBody() {
    // Clear any header attribute on the current line(s).
    _quillController.formatSelection(Attribute.clone(Attribute.h1, null));
    _refocus();
    if (mounted) setState(() {});
  }

  bool _isBodyLine() {
    return !_hasBlockStyle(Attribute.h1) &&
        !_hasBlockStyle(Attribute.h2) &&
        !_hasBlockStyle(Attribute.h3);
  }

  void _qfmt(Attribute attr) {
    final isBlock = attr.scope == AttributeScope.block;
    final hasIt = isBlock ? _hasBlockStyle(attr) : _hasInlineStyle(attr);
    if (hasIt) {
      _quillController.formatSelection(Attribute.clone(attr, null));
    } else {
      _quillController.formatSelection(attr);
    }
    _refocus();
    if (mounted) setState(() {});
  }

  bool _hasInlineStyle(Attribute attr) {
    final sel = _quillController.selection;
    if (!sel.isValid) return false;
    final offset = sel.start;
    final len = sel.isCollapsed ? 1 : sel.end - sel.start;
    final checkOffset =
        sel.isCollapsed && offset > 0 ? offset - 1 : offset;
    final style = _quillController.document.collectStyle(
        checkOffset.clamp(0, _quillController.document.length - 1),
        len.clamp(0, _quillController.document.length));
    return style.attributes.containsKey(attr.key);
  }

  bool _hasBlockStyle(Attribute attr) {
    final sel = _quillController.selection;
    final index = sel.isValid ? sel.start : 0;
    final style = _quillController.document.collectStyle(
        index.clamp(0, _quillController.document.length - 1), 0);
    final found = style.attributes[attr.key];
    if (found == null) return false;
    // For list/header values, ensure the actual value matches.
    if (attr.value != null) return found.value == attr.value;
    return true;
  }

  // ─── HTML SOURCE MODE ───

  void _toggleHtmlMode() {
    if (_htmlMode) {
      // Leaving HTML: parse the edited HTML back to a Delta document & save.
      try {
        final delta = QuillHtml.htmlToDelta(_sourceController.text);
        _suppressChanges = true;
        _quillController.document = delta.isEmpty
            ? Document()
            : Document.fromDelta(delta);
        _suppressChanges = false;
      } catch (e, st) {
        ErrorLogger.instance
            .warn('HTML → document failed', details: '$e\n$st');
        _suppressChanges = true;
        _quillController.document = Document()
          ..insert(0, _sourceController.text);
        _suppressChanges = false;
      }
      _lastContent =
          jsonEncode(_quillController.document.toDelta().toJson());
      _scheduleSave(_lastContent);
    } else {
      // Entering HTML: render the current document to HTML source text.
      try {
        _sourceController.text =
            QuillHtml.deltaToHtml(_quillController.document.toDelta());
      } catch (e, st) {
        ErrorLogger.instance
            .warn('Document → HTML failed', details: '$e\n$st');
        _sourceController.text = _quillController.document.toPlainText();
      }
    }
    setState(() => _htmlMode = !_htmlMode);
  }

  // ─── META BAR ───

  Widget _buildMetaBar(BuildContext context, Note note) {
    final s = S.of(context);
    final fmt = DateFormat.yMMMd(S.of(context).lang).add_Hm();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 3),
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Text(
          '${s.modified} ${fmt.format(note.modifiedAt)}',
          style: TextStyle(
              fontSize: 10,
              color: Theme.of(context)
                  .colorScheme
                  .onSurfaceVariant
                  .withValues(alpha: 0.45)),
        ),
      ),
    );
  }

  // ─── EDITOR BODY ───

  Widget _buildEditor(BuildContext context, Note note) {
    final settings = context.watch<AppSettings>();
    final bg = settings.darkEditorBg
        ? const Color(0xFF1E1E1E)
        : Theme.of(context).colorScheme.surface;
    final scale = settings.editorFontSize / 16.0;

    Widget child;
    if (_htmlMode) {
      child = TextField(
        controller: _sourceController,
        focusNode: _editorFocusNode,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        style: TextStyle(
            fontSize: 14 * scale,
            fontFamily: 'monospace',
            height: 1.6,
            color: settings.darkEditorBg ? Colors.white70 : null),
        decoration: const InputDecoration(
          hintText: '<p>HTML…</p>',
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(24),
        ),
        onChanged: (value) {
          _lastContent = value;
          _scheduleSave(value);
        },
      );
    } else {
      Widget quill = MediaQuery(
        // Apply the user's default text-size preference to all editor text.
        data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale)),
        child: QuillEditor.basic(
          controller: _quillController,
          focusNode: _editorFocusNode,
          scrollController: _scrollController,
          config: QuillEditorConfig(
            placeholder: S.of(context).startWriting,
            padding: const EdgeInsets.all(24),
            expands: true,
            autoFocus: false,
            embedBuilders: [
              _ImageEmbedBuilder(
                  onUpdate: _updateImage, onRemove: _removeEmbed),
              _TableEmbedBuilder(
                  onUpdate: _updateTable, onRemove: _removeEmbed),
            ],
            onLaunchUrl: (url) => _showLinkPopup(context, url),
          ),
        ),
      );
      // When the dark editor background is on under a light app theme, Quill's
      // default text colour would be dark-on-dark. Force a dark colour scheme
      // for the editor subtree so text, cursor and handles read as light.
      if (settings.darkEditorBg) {
        quill = Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Theme.of(context).colorScheme.primary,
              brightness: Brightness.dark,
            ).copyWith(surface: bg),
          ),
          child: quill,
        );
      }
      child = quill;
    }

    return Container(
      key: _editorKey,
      color: bg,
      child: Stack(children: [
        SafeArea(top: false, child: child),
        // Floating text-type controls that appear over a text selection.
        if (!_htmlMode) _buildFloatingSelectionBar(context),
      ]),
    );
  }

  /// Floating controls shown when text is selected: change the block to
  /// Body / Title / Heading / Subheading, plus quick inline styles.
  Widget _buildFloatingSelectionBar(BuildContext context) {
    final sel = _quillController.selection;
    if (!sel.isValid || sel.isCollapsed) return const SizedBox.shrink();
    final s = S.of(context);
    final theme = Theme.of(context);

    Widget pill(String label, bool active, VoidCallback onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Text(label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: active
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                )),
          ),
        );

    return Positioned(
      top: 8,
      left: 12,
      right: 12,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(12),
        color: theme.colorScheme.surfaceContainerHighest,
        clipBehavior: Clip.antiAlias,
        // Horizontally scrollable so the controls never overflow on narrow
        // (phone) widths; on wider screens the row simply fills the bar.
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              pill(s.body, _isBodyLine(), _setBody),
              _vline(theme),
              pill(s.title, _hasBlockStyle(Attribute.h1),
                  () => _qfmt(Attribute.h1)),
              pill(s.heading, _hasBlockStyle(Attribute.h2),
                  () => _qfmt(Attribute.h2)),
              pill('${s.heading} 3', _hasBlockStyle(Attribute.h3),
                  () => _qfmt(Attribute.h3)),
              _vline(theme),
              IconButton(
                icon: const Icon(Icons.format_bold, size: 18),
                visualDensity: VisualDensity.compact,
                isSelected: _hasInlineStyle(Attribute.bold),
                onPressed: () => _qfmt(Attribute.bold),
              ),
              IconButton(
                icon: const Icon(Icons.format_italic, size: 18),
                visualDensity: VisualDensity.compact,
                isSelected: _hasInlineStyle(Attribute.italic),
                onPressed: () => _qfmt(Attribute.italic),
              ),
              IconButton(
                icon: const Icon(Icons.link, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: () => _showInlineLinkEditor(context),
              ),
              _vline(theme),
              IconButton(
                icon: const Icon(Icons.format_align_left, size: 18),
                visualDensity: VisualDensity.compact,
                isSelected: _isAlign(null),
                onPressed: () => _applyAlign(null),
              ),
              IconButton(
                icon: const Icon(Icons.format_align_center, size: 18),
                visualDensity: VisualDensity.compact,
                isSelected: _isAlign('center'),
                onPressed: () => _applyAlign('center'),
              ),
              IconButton(
                icon: const Icon(Icons.format_align_right, size: 18),
                visualDensity: VisualDensity.compact,
                isSelected: _isAlign('right'),
                onPressed: () => _applyAlign('right'),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _vline(ThemeData theme) => Container(
        width: 1,
        height: 20,
        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
      );

  // ─── STATUS BAR ───

  Widget _buildStatusBar(BuildContext context, Note note) {
    final s = S.of(context);
    final plain = _htmlMode
        ? _sourceController.text
        : _quillController.document.toPlainText();
    final charCount = plain.replaceAll('\n', '').length;
    final wordCount = plain.trim().isEmpty
        ? 0
        : plain.trim().split(RegExp(r'\s+')).length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Row(children: [
        Text('$charCount ${s.chars} · $wordCount ${s.words}',
            style: TextStyle(
                fontSize: 10,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withValues(alpha: 0.5))),
      ]),
    );
  }

  // ─── INLINE LINK OVERLAY (no modal dialog) ───

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _showLinkPopup(BuildContext context, String url) {
    _removeOverlay();
    final s = S.of(context);
    _overlay = OverlayEntry(
      builder: (ctx) => _InlineOverlay(
        anchorKey: _editorKey,
        onDismiss: _removeOverlay,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(url,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: Colors.blue)),
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              _miniBtn(Icons.open_in_new, s.open, () {
                _removeOverlay();
                launchUrl(Uri.parse(url),
                    mode: LaunchMode.externalApplication);
              }),
              _miniBtn(Icons.copy, 'Copy', () {
                Clipboard.setData(ClipboardData(text: url));
                _removeOverlay();
              }),
              _miniBtn(Icons.edit, s.edit, () {
                _removeOverlay();
                _showInlineLinkEditor(context, editUrl: url);
              }),
            ]),
          ]),
        ),
      ),
    );
    Overlay.of(context).insert(_overlay!);
  }

  void _showInlineLinkEditor(BuildContext context, {String? editUrl}) {
    _removeOverlay();
    final s = S.of(context);
    final sel = _quillController.selection;
    final hasSelection = sel.isValid && !sel.isCollapsed;
    final selectedText = hasSelection
        ? _quillController.document
            .toPlainText()
            .substring(sel.start, sel.end)
        : '';
    final urlCtrl = TextEditingController(text: editUrl ?? '');
    final textCtrl = TextEditingController(text: selectedText);

    void apply() {
      final url = urlCtrl.text.trim();
      if (url.isEmpty) {
        _removeOverlay();
        return;
      }
      final text = textCtrl.text.trim().isNotEmpty
          ? textCtrl.text.trim()
          : url;
      if (hasSelection) {
        _quillController.replaceText(
            sel.start, sel.end - sel.start, text, null);
        _quillController.formatText(
            sel.start, text.length, LinkAttribute(url));
      } else {
        final offset = sel.isValid ? sel.start : _quillController.document.length - 1;
        _quillController.replaceText(offset, 0, text, null);
        _quillController.formatText(offset, text.length, LinkAttribute(url));
      }
      _removeOverlay();
      _refocus();
    }

    _overlay = OverlayEntry(
      builder: (ctx) => _InlineOverlay(
        anchorKey: _editorKey,
        onDismiss: _removeOverlay,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 280,
              child: TextField(
                controller: textCtrl,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  labelText: s.linkText,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: 280,
              child: TextField(
                controller: urlCtrl,
                autofocus: true,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'URL',
                  hintText: 'https://',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => apply(),
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (editUrl != null)
                _miniBtn(Icons.link_off, s.remove, () {
                  if (hasSelection) {
                    _quillController.formatText(sel.start,
                        sel.end - sel.start, LinkAttribute(null));
                  }
                  _removeOverlay();
                }),
              TextButton(onPressed: _removeOverlay, child: Text(s.cancel)),
              FilledButton(onPressed: apply, child: Text(s.save)),
            ]),
          ]),
        ),
      ),
    );
    Overlay.of(context).insert(_overlay!);
  }

  Widget _miniBtn(IconData icon, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  // ─── PHOTO ───

  void _attachPhoto(BuildContext context) async {
    try {
      // Returns a file path on native and a base64 `data:` URL on the web, so
      // the image is stored & rendered uniformly across platforms.
      final ref = await platform.pickImageRef();
      if (ref != null && ref.isNotEmpty) {
        _insertEmbedBlock(BlockEmbed.image(ref));
      }
    } catch (e, s) {
      ErrorLogger.instance.error('Insert image failed', details: '$e\n$s');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not insert image: $e')),
        );
      }
    }
    _refocus();
  }

  // ─── MOVE ───

  void _showMoveDialog(BuildContext context, Note note) {
    final s = S.of(context);
    final folders = context.read<FoldersProvider>().folders;
    final selected = Set<String>.from(note.folderIds);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(s.assignToFolders),
          content: SizedBox(
            width: 300,
            child: folders.isEmpty
                ? Text(s.noNotesFound)
                : Column(mainAxisSize: MainAxisSize.min, children: [
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
                  ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
            FilledButton(
                onPressed: () {
                  context
                      .read<NotesProvider>()
                      .moveNoteToFolder(note, selected.toList());
                  context.read<FoldersProvider>().refreshCounts();
                  Navigator.pop(ctx);
                },
                child: Text(s.ok)),
          ],
        ),
      ),
    );
  }

  // ─── EXPORT ───

  Future<void> _exportNoteWithPicker(BuildContext context, Note note) async {
    final format = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(S.of(context).export),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'txt'),
            child: const Row(children: [
              Icon(Icons.text_snippet, size: 20),
              SizedBox(width: 12),
              Text('Plain Text (.txt)'),
            ]),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'md'),
            child: const Row(children: [
              Icon(Icons.code, size: 20),
              SizedBox(width: 12),
              Text('Markdown (.md)'),
            ]),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'html'),
            child: const Row(children: [
              Icon(Icons.html, size: 20),
              SizedBox(width: 12),
              Text('HTML (.html)'),
            ]),
          ),
        ],
      ),
    );
    if (format == null || !context.mounted) return;

    try {
      final name = note.displayTitle.isNotEmpty
          ? note.displayTitle.replaceAll(RegExp(r'[^\w\s]'), '_').trim()
          : 'note';
      final ext = format;

      String content;
      if (format == 'md') {
        try {
          content =
              DeltaToMarkdown().convert(_quillController.document.toDelta());
        } catch (_) {
          content = _quillController.document.toPlainText();
        }
      } else if (format == 'html') {
        final body = QuillHtml.deltaToHtml(_quillController.document.toDelta());
        content =
            '<!DOCTYPE html>\n<html>\n<head>\n<meta charset="utf-8">\n'
            '<title>${note.displayTitle}</title>\n</head>\n<body>\n'
            '$body\n</body>\n</html>\n';
      } else {
        content = _quillController.document.toPlainText();
      }
      final saved =
          await platform.saveText('$name.$ext', content, extensions: [ext]);
      if (!saved) return;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Exported'),
              duration: Duration(seconds: 2)),
        );
      }
    } catch (e, s) {
      ErrorLogger.instance.error('Note export failed', details: '$e\n$s');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Export failed: $e'),
              duration: const Duration(seconds: 2)),
        );
      }
    }
  }

  void _confirmPermanentDelete(BuildContext context, Note note) {
    final s = S.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteForever),
        content: const Text(
            'Permanently delete this note? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              context.read<NotesProvider>().permanentlyDeleteNote(note.id);
              context.read<FoldersProvider>().refreshCounts();
              Navigator.pop(ctx);
            },
            child: Text(s.deleteForever),
          ),
        ],
      ),
    );
  }
}

/// A dismiss-on-tap-outside overlay anchored just under the editor's top edge.
class _InlineOverlay extends StatelessWidget {
  final GlobalKey anchorKey;
  final VoidCallback onDismiss;
  final Widget child;

  const _InlineOverlay({
    required this.anchorKey,
    required this.onDismiss,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final box =
        anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final offset = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final width = box?.size.width ?? MediaQuery.of(context).size.width;
    final top = offset.dy + 8;
    final left = offset.dx + (width > 320 ? (width - 300) / 2 : 8);

    return Stack(children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: onDismiss,
        ),
      ),
      Positioned(
        left: left,
        top: top,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: child,
          ),
        ),
      ),
    ]);
  }
}

/// A small editable text combo for the toolbar: shows the active value, lets
/// the user type a new one (Enter applies), and a dropdown arrow opens a list
/// of presets — filtered by what's typed — or a custom picker via
/// [onDropdownTap]. Lives outside any focus barrier so the field is editable.
class _ToolbarComboField extends StatefulWidget {
  final String value;
  final double width;
  final bool enabled;
  final String? hint;
  final TextInputType? keyboardType;
  final List<String> presets;
  final VoidCallback? onDropdownTap;
  final ValueChanged<String> onSubmit;

  const _ToolbarComboField({
    required this.value,
    required this.width,
    required this.onSubmit,
    this.enabled = true,
    this.hint,
    this.keyboardType,
    this.presets = const [],
    this.onDropdownTap,
  });

  @override
  State<_ToolbarComboField> createState() => _ToolbarComboFieldState();
}

class _ToolbarComboFieldState extends State<_ToolbarComboField> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.value);
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(covariant _ToolbarComboField old) {
    super.didUpdateWidget(old);
    // Reflect the active value from the editor, but never while the user is
    // mid-edit in this field.
    if (!_focus.hasFocus && widget.value != _ctrl.text) {
      _ctrl.text = widget.value;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _openMenu(Offset pos) async {
    if (widget.onDropdownTap != null) {
      widget.onDropdownTap!();
      return;
    }
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final typed = _ctrl.text.trim().toLowerCase();
    final filtered = widget.presets
        .where((p) => typed.isEmpty || p.toLowerCase().contains(typed))
        .toList();
    final list = filtered.isEmpty ? widget.presets : filtered;
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
          pos & const Size(40, 40), Offset.zero & overlay.size),
      items: [
        for (final p in list) PopupMenuItem(value: p, child: Text(p)),
      ],
    );
    if (v != null) {
      _ctrl.text = v;
      widget.onSubmit(v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = widget.enabled
        ? theme.colorScheme.onSurface
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3);
    return Container(
      width: widget.width,
      height: 30,
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            enabled: widget.enabled,
            keyboardType: widget.keyboardType,
            textInputAction: TextInputAction.done,
            style: TextStyle(fontSize: 12, color: fg),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: widget.hint,
              hintStyle: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.5)),
              contentPadding: EdgeInsets.zero,
            ),
            onSubmitted: widget.onSubmit,
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown:
              widget.enabled ? (d) => _openMenu(d.globalPosition) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(Icons.arrow_drop_down, size: 18, color: fg),
          ),
        ),
      ]),
    );
  }
}

/// Google-Docs–style table-size grid: hover (desktop) or tap (mobile) a cell to
/// choose the dimensions. Pops `[rows, cols]`.
class _TableSizePicker extends StatefulWidget {
  @override
  State<_TableSizePicker> createState() => _TableSizePickerState();
}

class _TableSizePickerState extends State<_TableSizePicker> {
  // The grid starts small and grows as you reach its edge (capped), so a table
  // can be made as large as you like, Google-Docs style.
  static const int _hardCap = 30;
  int _gridRows = 6;
  int _gridCols = 8;
  int _rows = 0;
  int _cols = 0;

  void _hover(int r, int c) {
    setState(() {
      _rows = r;
      _cols = c;
      if (r == _gridRows && _gridRows < _hardCap) _gridRows++;
      if (c == _gridCols && _gridCols < _hardCap) _gridCols++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380, maxHeight: 380),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (int r = 1; r <= _gridRows; r++)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    for (int c = 1; c <= _gridCols; c++)
                      MouseRegion(
                        onEnter: (_) => _hover(r, c),
                        child: GestureDetector(
                          onTap: () => Navigator.pop(context, [r, c]),
                          child: Container(
                            width: 18,
                            height: 18,
                            margin: const EdgeInsets.all(1),
                            decoration: BoxDecoration(
                              color: (r <= _rows && c <= _cols)
                                  ? theme.colorScheme.primary
                                      .withValues(alpha: 0.65)
                                  : theme.colorScheme.surfaceContainerHighest,
                              border: Border.all(
                                  color: theme.colorScheme.outlineVariant),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                  ]),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _rows == 0 ? S.of(context).insertTable : '$_cols × $_rows',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

/// Palette used for table-cell backgrounds (and reused elsewhere).
const List<String?> _cellPalette = [
  null, // clear
  '#fce8e6', '#fef7e0', '#e6f4ea', '#e8f0fe', '#f3e8fd',
  '#f1f3f4', '#d93025', '#f9ab00', '#188038', '#1a73e8',
];

/// Renders a real, editable table from a `table` block embed. Data is JSON:
/// `{"rows": [[..]], "fmt": {"r_c": {"bg": "#hex", "align": "center"}},
///   "border": "all|none|horizontal"}`.
class _TableEmbedBuilder extends EmbedBuilder {
  final void Function(int docOffset, String newJson)? onUpdate;
  final void Function(int docOffset)? onRemove;
  _TableEmbedBuilder({this.onUpdate, this.onRemove});

  @override
  String get key => 'table';

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final raw = embedContext.node.value.data;
    List<List<String>> rows;
    Map<String, dynamic> fmt = {};
    String border = 'all';
    try {
      final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
      rows = (decoded['rows'] as List)
          .map<List<String>>(
              (r) => (r as List).map((c) => c.toString()).toList())
          .toList();
      if (decoded['fmt'] is Map) {
        fmt = (decoded['fmt'] as Map).cast<String, dynamic>();
      }
      border = decoded['border'] as String? ?? 'all';
    } catch (_) {
      rows = [
        ['', '']
      ];
    }
    final readOnly = embedContext.readOnly || onUpdate == null;
    final offset = embedContext.node.documentOffset;
    return _TableWidget(
      // Key by offset+shape so the widget rebuilds cleanly when data changes.
      key: ValueKey(
          'table_${offset}_${rows.length}x${rows.isEmpty ? 0 : rows.first.length}'),
      rows: rows,
      fmt: fmt,
      border: border,
      readOnly: readOnly,
      onChanged: (json) => onUpdate?.call(offset, json),
      onRemove: onRemove == null ? null : () => onRemove!.call(offset),
    );
  }
}

class _TableWidget extends StatefulWidget {
  final List<List<String>> rows;
  final Map<String, dynamic> fmt;
  final String border;
  final bool readOnly;
  final ValueChanged<String> onChanged;
  final VoidCallback? onRemove;

  const _TableWidget({
    super.key,
    required this.rows,
    required this.fmt,
    required this.border,
    required this.readOnly,
    required this.onChanged,
    this.onRemove,
  });

  @override
  State<_TableWidget> createState() => _TableWidgetState();
}

class _TableWidgetState extends State<_TableWidget> {
  late List<List<TextEditingController>> _cells;
  late List<List<FocusNode>> _nodes;
  late Map<String, Map<String, String>> _fmt;
  late String _border;
  int? _fr; // focused row
  int? _fc; // focused col

  @override
  void initState() {
    super.initState();
    _cells = widget.rows
        .map((r) => r.map((c) => TextEditingController(text: c)).toList())
        .toList();
    _fmt = {};
    widget.fmt.forEach((k, v) {
      if (v is Map) {
        _fmt[k] = v.map((a, b) => MapEntry(a.toString(), b.toString()));
      }
    });
    _border = widget.border;
    _nodes = [];
    for (var r = 0; r < _cells.length; r++) {
      final row = <FocusNode>[];
      for (var c = 0; c < _cells[r].length; c++) {
        final rr = r, cc = c;
        final fn = FocusNode();
        fn.addListener(() {
          if (fn.hasFocus && mounted) {
            setState(() {
              _fr = rr;
              _fc = cc;
            });
          }
        });
        row.add(fn);
      }
      _nodes.add(row);
    }
  }

  @override
  void dispose() {
    for (final row in _cells) {
      for (final c in row) {
        c.dispose();
      }
    }
    for (final row in _nodes) {
      for (final n in row) {
        n.dispose();
      }
    }
    super.dispose();
  }

  String _json([List<List<String>>? rows,
      Map<String, Map<String, String>>? fmt]) {
    return jsonEncode({
      'rows': rows ??
          _cells.map((r) => r.map((c) => c.text).toList()).toList(),
      'fmt': fmt ?? _fmt,
      'border': _border,
    });
  }

  void _commit() => widget.onChanged(_json());

  void _addRow() {
    final cols = _cells.isEmpty ? 2 : _cells.first.length;
    final rows = _cells.map((r) => r.map((c) => c.text).toList()).toList()
      ..add(List.filled(cols, ''));
    widget.onChanged(_json(rows));
  }

  void _addColumn() {
    final rows =
        _cells.map((r) => [...r.map((c) => c.text), '']).toList();
    widget.onChanged(_json(rows));
  }

  void _deleteRow(int target) {
    if (_cells.length <= 1) return;
    final rows = _cells.map((r) => r.map((c) => c.text).toList()).toList()
      ..removeAt(target);
    final newFmt = <String, Map<String, String>>{};
    _fmt.forEach((k, v) {
      final p = k.split('_');
      final rr = int.parse(p[0]), cc = int.parse(p[1]);
      if (rr == target) return;
      newFmt['${rr > target ? rr - 1 : rr}_$cc'] = v;
    });
    _fr = null;
    _fc = null;
    widget.onChanged(_json(rows, newFmt));
  }

  void _deleteColumn(int target) {
    if (_cells.isEmpty || _cells.first.length <= 1) return;
    final rows = _cells
        .map((r) => [
              for (var c = 0; c < r.length; c++)
                if (c != target) r[c].text
            ])
        .toList();
    final newFmt = <String, Map<String, String>>{};
    _fmt.forEach((k, v) {
      final p = k.split('_');
      final rr = int.parse(p[0]), cc = int.parse(p[1]);
      if (cc == target) return;
      newFmt['${rr}_${cc > target ? cc - 1 : cc}'] = v;
    });
    _fr = null;
    _fc = null;
    widget.onChanged(_json(rows, newFmt));
  }

  void _setCellAttr(int r, int c, String key, String? value) {
    final ck = '${r}_$c';
    final m = Map<String, String>.from(_fmt[ck] ?? {});
    if (value == null) {
      m.remove(key);
    } else {
      m[key] = value;
    }
    if (m.isEmpty) {
      _fmt.remove(ck);
    } else {
      _fmt[ck] = m;
    }
    setState(() {});
    _commit();
  }

  void _cycleBorder() {
    const order = ['all', 'horizontal', 'none'];
    final next = order[(order.indexOf(_border) + 1) % order.length];
    setState(() => _border = next);
    _commit();
  }

  TableBorder _tableBorder(Color color) {
    switch (_border) {
      case 'none':
        return const TableBorder();
      case 'horizontal':
        return TableBorder.symmetric(
            inside: BorderSide(color: color), outside: BorderSide.none);
      default:
        return TableBorder.all(color: color);
    }
  }

  TextAlign _alignOf(int r, int c) {
    switch (_fmt['${r}_$c']?['align']) {
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      default:
        return TextAlign.left;
    }
  }

  Color? _bgOf(int r, int c) {
    final hex = _fmt['${r}_$c']?['bg'];
    if (hex == null || hex.length < 7) return null;
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outlineVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      // Absorb stray taps so they don't select the whole table embed in Quill.
      child: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: () {},
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!widget.readOnly && _fr != null && _fc != null)
              _buildCellToolbar(context),
            Table(
              border: _tableBorder(borderColor),
              defaultColumnWidth: const IntrinsicColumnWidth(),
              children: [
                for (var r = 0; r < _cells.length; r++)
                  TableRow(
                    children: [
                      for (var c = 0; c < _cells[r].length; c++)
                        Container(
                          color: _bgOf(r, c) ??
                              (r == 0
                                  ? theme.colorScheme.surfaceContainerHighest
                                  : null),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minWidth: 80),
                            child: TextField(
                              controller: _cells[r][c],
                              focusNode: _nodes[r][c],
                              readOnly: widget.readOnly,
                              maxLines: null,
                              textAlign: _alignOf(r, c),
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: r == 0
                                      ? FontWeight.w600
                                      : FontWeight.normal),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.zero,
                              ),
                              onEditingComplete: _commit,
                              onTapOutside: (_) => _commit(),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            if (!widget.readOnly)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(children: [
                  // The leading "+" comes from the icon; the label is just the
                  // word, so this renders as "+ Row" / "+ Col" (not "+ + Row").
                  _tableActionButton(
                      Icons.add, S.of(context).row, _addRow),
                  _tableActionButton(
                      Icons.add, S.of(context).col, _addColumn),
                  if (widget.onRemove != null)
                    _tableActionButton(
                      Icons.delete_outline,
                      S.of(context).deleteTable,
                      widget.onRemove!,
                      danger: true,
                    ),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tableActionButton(IconData icon, String label, VoidCallback onTap,
      {bool danger = false}) {
    final color = danger ? Theme.of(context).colorScheme.error : null;
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 14, color: color),
      label: Text(label, style: TextStyle(fontSize: 11, color: color)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  /// Per-cell formatting bar shown while a cell is focused: background color,
  /// alignment, table border style, and row/column deletion.
  Widget _buildCellToolbar(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final r = _fr!, c = _fc!;
    final activeAlign = _fmt['${r}_$c']?['align'] ?? 'left';
    Widget iconBtn(IconData icon, String tip, bool active, VoidCallback tap) {
      return Tooltip(
        message: tip,
        child: InkWell(
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(6),
          onTap: tap,
          child: Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: active
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
                  : null,
            ),
            child: Icon(icon,
                size: 16,
                color: active
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Tooltip(message: s.cellColor, child: const Icon(Icons.format_color_fill, size: 15)),
          for (final hex in _cellPalette)
            InkWell(
              canRequestFocus: false,
              onTap: () => _setCellAttr(r, c, 'bg', hex),
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: hex == null
                      ? theme.colorScheme.surface
                      : Color(int.parse('FF${hex.substring(1)}', radix: 16)),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: theme.colorScheme.outlineVariant
                          .withValues(alpha: 0.6)),
                ),
                child: hex == null
                    ? const Icon(Icons.format_color_reset, size: 12)
                    : null,
              ),
            ),
          const SizedBox(width: 2),
          iconBtn(Icons.format_align_left, s.alignLeft, activeAlign == 'left',
              () => _setCellAttr(r, c, 'align', null)),
          iconBtn(Icons.format_align_center, s.alignCenter,
              activeAlign == 'center', () => _setCellAttr(r, c, 'align', 'center')),
          iconBtn(Icons.format_align_right, s.alignRight,
              activeAlign == 'right', () => _setCellAttr(r, c, 'align', 'right')),
          const SizedBox(width: 2),
          iconBtn(Icons.border_all, s.border, false, _cycleBorder),
          iconBtn(Icons.delete_sweep_outlined, s.deleteRow, false,
              () => _deleteRow(r)),
          iconBtn(Icons.delete_outline, s.deleteColumn, false,
              () => _deleteColumn(c)),
        ],
      ),
    );
  }
}

/// Builds the right image widget for an embed reference, regardless of how the
/// attachment is stored: an inline base64 `data:` URL (web attachments &
/// cross-platform imports), an `http(s)` URL, or a local file path (native
/// attachments). Keeps a single rendering path so notes display identically on
/// every platform.
Widget _buildImageSource(String ref, {Key? key, double? width, BoxFit? fit}) {
  Widget broken(BuildContext context) => Container(
        height: 100,
        width: width,
        color: Colors.grey.shade200,
        child: const Center(child: Icon(Icons.broken_image, size: 32)),
      );

  if (ref.startsWith('data:')) {
    try {
      final bytes = base64Decode(ref.substring(ref.indexOf(',') + 1));
      return Image.memory(
        bytes,
        key: key,
        width: width,
        fit: fit,
        errorBuilder: (c, _, _) => broken(c),
      );
    } catch (_) {
      return Builder(key: key, builder: broken);
    }
  }
  if (ref.startsWith('http://') || ref.startsWith('https://')) {
    return Image.network(
      ref,
      key: key,
      width: width,
      fit: fit,
      errorBuilder: (c, _, _) => broken(c),
    );
  }
  return platform.buildFileImage(
    ref,
    imageKey: key,
    width: width,
    fit: fit,
    errorBuilder: broken,
  );
}

/// Renders an image embed. Data is either a plain file path (legacy) or JSON:
/// `{"path": ..., "width": 400, "link": "https://..."}`. Tapping (in an
/// editable note) opens a menu to resize, add/edit a link, or delete it.
class _ImageEmbedBuilder extends EmbedBuilder {
  final void Function(int docOffset, String newData)? onUpdate;
  final void Function(int docOffset)? onRemove;
  _ImageEmbedBuilder({this.onUpdate, this.onRemove});

  @override
  String get key => BlockEmbed.imageType;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    final raw = embedContext.node.value.data as String;
    String path = raw;
    double? width;
    String? link;
    if (raw.trimLeft().startsWith('{')) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        path = m['path'] as String? ?? raw;
        width = (m['width'] as num?)?.toDouble();
        link = m['link'] as String?;
      } catch (_) {}
    }
    final offset = embedContext.node.documentOffset;
    final readOnly = embedContext.readOnly || onUpdate == null;
    return _ImageWidget(
      path: path,
      width: width,
      link: link,
      readOnly: readOnly,
      onChange: (w, l) => onUpdate?.call(
          offset, jsonEncode({'path': path, 'width': w, 'link': l})),
      onRemove: () => onRemove?.call(offset),
    );
  }
}

class _ImageWidget extends StatefulWidget {
  final String path;
  final double? width;
  final String? link;
  final bool readOnly;
  final void Function(double? width, String? link) onChange;
  final VoidCallback onRemove;

  const _ImageWidget({
    required this.path,
    required this.width,
    required this.link,
    required this.readOnly,
    required this.onChange,
    required this.onRemove,
  });

  @override
  State<_ImageWidget> createState() => _ImageWidgetState();
}

class _ImageWidgetState extends State<_ImageWidget> {
  final GlobalKey _imgKey = GlobalKey();
  double? _w; // live width while dragging the resize handle

  @override
  void initState() {
    super.initState();
    _w = widget.width;
  }

  @override
  void didUpdateWidget(covariant _ImageWidget old) {
    super.didUpdateWidget(old);
    if (old.width != widget.width) _w = widget.width;
  }

  void _menu(BuildContext context, Offset pos) async {
    final s = S.of(context);
    final link = widget.link;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
          pos & const Size(40, 40), Offset.zero & overlay.size),
      items: [
        PopupMenuItem(value: 'w200', child: Text('${s.resize}: ${s.small}')),
        PopupMenuItem(value: 'w400', child: Text('${s.resize}: ${s.medium}')),
        PopupMenuItem(value: 'w640', child: Text('${s.resize}: ${s.large}')),
        PopupMenuItem(value: 'wfull', child: Text('${s.resize}: ${s.fullWidth}')),
        PopupMenuItem(
            value: 'link', child: Text(link == null ? s.addLink : s.editLink)),
        if (link != null) ...[
          PopupMenuItem(value: 'open', child: Text(s.open)),
          PopupMenuItem(value: 'unlink', child: Text(s.removeLink)),
        ],
        PopupMenuItem(
            value: 'delete',
            child: Text(s.delete,
                style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ],
    );
    switch (v) {
      case 'w200':
        widget.onChange(200, link);
        break;
      case 'w400':
        widget.onChange(400, link);
        break;
      case 'w640':
        widget.onChange(640, link);
        break;
      case 'wfull':
        widget.onChange(null, link);
        break;
      case 'link':
        if (context.mounted) _editLink(context);
        break;
      case 'open':
        if (link != null) {
          launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
        }
        break;
      case 'unlink':
        widget.onChange(widget.width, null);
        break;
      case 'delete':
        widget.onRemove();
        break;
    }
  }

  void _editLink(BuildContext context) async {
    final s = S.of(context);
    final ctrl = TextEditingController(text: widget.link ?? '');
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.addLink),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
              hintText: 'https://', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(s.save)),
        ],
      ),
    );
    if (res != null) widget.onChange(widget.width, res.isEmpty ? null : res);
  }

  void _onDragStart(double maxW) {
    if (_w == null) {
      final box = _imgKey.currentContext?.findRenderObject() as RenderBox?;
      _w = box?.size.width ?? maxW;
    }
  }

  Widget _resizeHandle(double maxW) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.resizeUpLeftDownRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => _onDragStart(maxW),
        onPanUpdate: (d) => setState(() {
          _w = ((_w ?? maxW) + d.delta.dx).clamp(60.0, maxW);
        }),
        onPanEnd: (_) => widget.onChange(_w, widget.link),
        child: Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 2),
            ],
          ),
          child: const Icon(Icons.open_in_full,
              size: 11, color: Colors.white),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final maxW = constraints.maxWidth.isFinite
          ? constraints.maxWidth
          : MediaQuery.of(context).size.width;
      final w = _w;

      Widget image = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: w == null ? 300 : 2000),
          child: _buildImageSource(
            widget.path,
            key: _imgKey,
            width: w,
            fit: w == null ? BoxFit.contain : BoxFit.cover,
          ),
        ),
      );

      final stack = Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: widget.readOnly
                ? null
                : (d) => _menu(context, d.globalPosition),
            child: MouseRegion(
              cursor: widget.readOnly
                  ? SystemMouseCursors.basic
                  : SystemMouseCursors.click,
              child: image,
            ),
          ),
          if (widget.link != null)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.link, size: 14, color: Colors.white),
              ),
            ),
          // Round drag handle at the bottom-right corner (editable notes only).
          if (!widget.readOnly)
            Positioned(
              right: -6,
              bottom: -6,
              child: _resizeHandle(maxW),
            ),
        ],
      );

      return Container(
        padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
        alignment: Alignment.centerLeft,
        child: stack,
      );
    });
  }
}
