// Settings page: appearance (theme/accent/language), editor defaults, sort
// order, security (lock password), data export/import, and diagnostics. Shown
// embedded in the desktop right-pane or pushed as a route on mobile.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../providers/app_settings.dart';
import '../providers/notes_provider.dart';
import '../providers/folders_provider.dart';
import '../services/data_transfer_service.dart';
import '../services/error_logger.dart';
import '../l10n/strings.dart';
import 'error_log_screen.dart';

class SettingsScreen extends StatelessWidget {
  /// When provided, the screen is embedded in the desktop right-pane and the
  /// back button calls this instead of popping a route (keeps sidebars visible).
  final VoidCallback? onClose;

  const SettingsScreen({super.key, this.onClose});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();
    final s = S.of(context);
    final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    // Pushed as a standalone route on mobile (not embedded, not desktop): give
    // it a real AppBar so there's a back button.
    final isMobileRoute = !isDesktop && onClose == null;

    return Scaffold(
      appBar: isMobileRoute ? AppBar(title: Text(s.settings)) : null,
      body: Column(
        children: [
          if (isDesktop || onClose != null) _buildTitleBar(context, s),
          Expanded(child: ListView(children: [
            const SizedBox(height: 8),
            _sectionHeader(context, s.appearance),
            _themePicker(context, settings, s),
            const Divider(indent: 16),
            _colorPresets(context, settings, s),
            const Divider(indent: 16),
            _languagePicker(context, settings, s),
            const SizedBox(height: 16),
            _sectionHeader(context, s.editor),
            _defaultNoteFormat(context, settings, s),
            const Divider(indent: 16),
            _textSizeSlider(context, settings, s),
            const Divider(indent: 16),
            SwitchListTile(
              secondary: const Icon(Icons.invert_colors),
              title: Text(s.darkEditorBg),
              value: settings.darkEditorBg,
              onChanged: (v) => settings.setDarkEditorBg(v),
            ),
            const SizedBox(height: 16),
            _sectionHeader(context, s.sorting),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                ...NotesSortOrder.values.map((o) => RadioListTile<NotesSortOrder>(
                      title: Text(_sortLabel(o, s)),
                      value: o,
                      // ignore: deprecated_member_use
                      groupValue: settings.sortOrder,
                      // ignore: deprecated_member_use
                      onChanged: (v) {
                        if (v != null) {
                          settings.setSortOrder(v);
                          context.read<NotesProvider>().sortNotes(v);
                        }
                      },
                      dense: true,
                    )),
              ]),
            ),
            const SizedBox(height: 16),
            _sectionHeader(context, s.security),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: Text(s.lockPassword),
              subtitle: Text(settings.lockPassword != null
                  ? '••••••••'
                  : '—'),
              onTap: () => _showPasswordDialog(context, settings, s),
            ),
            const SizedBox(height: 16),
            _sectionHeader(context, s.data),
            ListTile(
              leading: const Icon(Icons.upload_file_outlined),
              title: Text(s.exportAllData),
              subtitle: Text(s.exportImportSubtitle),
              onTap: () => _exportAll(context, s),
            ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(s.importData),
              subtitle: Text(s.exportImportSubtitle),
              onTap: () => _importAll(context, s),
            ),
            const SizedBox(height: 16),
            _sectionHeader(context, s.diagnostics),
            ListTile(
              leading: const Icon(Icons.bug_report_outlined),
              title: Text(s.errorLog),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ErrorLogScreen()),
              ),
            ),
            const SizedBox(height: 32),
          ])),
        ],
      ),
    );
  }

  // ─── DATA EXPORT / IMPORT ───

  Future<void> _exportAll(BuildContext context, S s) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ts = DateTime.now().toIso8601String().split('T').first;
      final path = await FilePicker.platform.saveFile(
        dialogTitle: s.exportAllData,
        fileName: 'bellonotes_backup_$ts.zip',
        allowedExtensions: ['zip'],
        type: FileType.custom,
      );
      if (path == null) return;
      final dest = path.endsWith('.zip') ? path : '$path.zip';
      final count = await DataTransferService.exportToZip(dest);
      messenger.showSnackBar(
        SnackBar(content: Text('${s.exportAllData}: $count → $dest')),
      );
    } catch (e, st) {
      ErrorLogger.instance.error('Data export failed', details: '$e\n$st');
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  Future<void> _importAll(BuildContext context, S s) async {
    final messenger = ScaffoldMessenger.of(context);
    final notesProvider = context.read<NotesProvider>();
    final foldersProvider = context.read<FoldersProvider>();
    try {
      final result = await FilePicker.platform.pickFiles(
        dialogTitle: s.importData,
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      final path = result?.files.single.path;
      if (path == null) return;
      final count = await DataTransferService.importFromZip(path);
      await foldersProvider.loadFolders();
      await notesProvider.loadNotes(folderId: 'all');
      messenger.showSnackBar(
        SnackBar(content: Text('${s.importData}: $count')),
      );
    } catch (e, st) {
      ErrorLogger.instance.error('Data import failed', details: '$e\n$st');
      messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  // ─── UI helpers ───

  Widget _buildTitleBar(BuildContext context, S s) {
    final theme = Theme.of(context);
    final embedded = onClose != null;
    // Only a full-window macOS title bar needs to clear the traffic lights; an
    // embedded pane (and Windows/Linux) does not.
    final leftPad = embedded ? 8.0 : (Platform.isMacOS ? 78.0 : 12.0);
    return Container(
      height: 38,
      padding: EdgeInsets.only(left: leftPad),
      color: theme.colorScheme.surfaceContainerLowest,
      child: Row(children: [
        IconButton(
          icon: Icon(embedded ? Icons.close : Icons.arrow_back, size: 16),
          onPressed: () =>
              embedded ? onClose!() : Navigator.of(context).pop(),
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          iconSize: 16,
        ),
        const Spacer(),
        Text(s.settings,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface)),
        const Spacer(),
        // Balance the leading close button + padding so the title stays centred.
        SizedBox(width: leftPad + 36),
      ]),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(title,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.primary,
              letterSpacing: 0.5)),
    );
  }

  Widget _themePicker(BuildContext context, AppSettings settings, S s) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        const Padding(
          padding: EdgeInsets.only(left: 8),
          child: Icon(Icons.brightness_6),
        ),
        const SizedBox(width: 16),
        Text(s.theme, style: const TextStyle(fontSize: 14)),
        const Spacer(),
        SegmentedButton<ThemeMode>(
          segments: [
            ButtonSegment(
                value: ThemeMode.system,
                label: Text(s.auto),
                icon: const Icon(Icons.auto_awesome, size: 14)),
            ButtonSegment(
                value: ThemeMode.light,
                label: Text(s.light),
                icon: const Icon(Icons.light_mode, size: 14)),
            ButtonSegment(
                value: ThemeMode.dark,
                label: Text(s.dark),
                icon: const Icon(Icons.dark_mode, size: 14)),
          ],
          selected: {settings.themeMode},
          onSelectionChanged: (sel) => settings.setThemeMode(sel.first),
          style: const ButtonStyle(visualDensity: VisualDensity.compact),
        ),
        const SizedBox(width: 8),
      ]),
    );
  }

  Widget _colorPresets(BuildContext context, AppSettings settings, S s) {
    const presets = <int>[
      0xFFF5A623, // amber (default)
      0xFF1A73E8, // blue
      0xFF188038, // green
      0xFF7B1FA2, // purple
      0xFFD93025, // red
      0xFF00897B, // teal
      0xFFC2185B, // pink
      0xFF3949AB, // indigo
      0xFF5D4037, // brown
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(children: [
        const Icon(Icons.palette_outlined),
        const SizedBox(width: 16),
        Text(s.themeColor, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 16),
        // Expanded gives the Wrap a bounded width so the swatches flow onto a
        // second row on narrow screens instead of overflowing horizontally.
        Expanded(
          child: Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
            for (final c in presets)
              GestureDetector(
                onTap: () => settings.setSeedColor(c),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Color(c),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: settings.seedColorValue == c
                          ? Theme.of(context).colorScheme.onSurface
                          : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                  child: settings.seedColorValue == c
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _languagePicker(BuildContext context, AppSettings settings, S s) {
    const langs = [
      ('en', 'English'),
      ('fr', 'Français'),
      ('ar', 'العربية'),
      ('zh', '中文'),
      ('it', 'Italiano'),
      ('es', 'Español'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        const Padding(
          padding: EdgeInsets.only(left: 8),
          child: Icon(Icons.language),
        ),
        const SizedBox(width: 16),
        Text(s.language, style: const TextStyle(fontSize: 14)),
        const Spacer(),
        DropdownButton<String>(
          value: settings.locale.languageCode,
          underline: const SizedBox(),
          items: langs
              .map((l) => DropdownMenuItem(
                    value: l.$1,
                    child: Text(l.$2, style: const TextStyle(fontSize: 13)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) settings.setLocale(Locale(v));
          },
        ),
        const SizedBox(width: 8),
      ]),
    );
  }

  Widget _defaultNoteFormat(BuildContext context, AppSettings settings, S s) {
    final formats = {
      'title': s.title,
      'heading': s.heading,
      'subheading': '${s.heading} 3',
      'body': s.body,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(children: [
        const Padding(
          padding: EdgeInsets.only(left: 8),
          child: Icon(Icons.text_fields),
        ),
        const SizedBox(width: 16),
        Expanded(
            child: Text(s.newNotesStartWith,
                style: const TextStyle(fontSize: 14))),
        DropdownButton<String>(
          value: settings.defaultFormat,
          underline: const SizedBox(),
          items: formats.entries
              .map((e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value, style: const TextStyle(fontSize: 13)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) settings.setDefaultFormat(v);
          },
        ),
        const SizedBox(width: 8),
      ]),
    );
  }

  Widget _textSizeSlider(BuildContext context, AppSettings settings, S s) {
    return ListTile(
      leading: const Icon(Icons.format_size),
      title: Row(children: [
        Text(s.defaultTextSize, style: const TextStyle(fontSize: 14)),
        const Spacer(),
        Text(
          ['', 'XS', 'S', 'M', 'L', 'XL'][settings.defaultTextSize],
          style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ]),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          const Text('A', style: TextStyle(fontSize: 11)),
          Expanded(
            child: Slider(
              value: settings.defaultTextSize.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              onChanged: (v) => settings.setDefaultTextSize(v.round()),
            ),
          ),
          const Text('A',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  void _showPasswordDialog(BuildContext context, AppSettings settings, S s) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.lockPassword),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: '••••••••',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
          FilledButton(
              onPressed: () {
                final pw = ctrl.text.trim();
                settings.setLockPassword(pw.isEmpty ? null : pw);
                Navigator.pop(ctx);
              },
              child: Text(s.save)),
        ],
      ),
    );
  }

  String _sortLabel(NotesSortOrder o, S s) {
    switch (o) {
      case NotesSortOrder.dateNewest:
        return '${s.modified} ↓';
      case NotesSortOrder.dateOldest:
        return '${s.modified} ↑';
      case NotesSortOrder.titleAz:
        return '${s.title} A-Z';
      case NotesSortOrder.titleZa:
        return '${s.title} Z-A';
    }
  }
}
