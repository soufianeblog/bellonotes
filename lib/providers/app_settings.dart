// ChangeNotifier holding user preferences — theme, accent color, language,
// default note format/size, sort order, lock password — persisted via the
// platform bridge (a JSON file on native, localStorage on the web) and reloaded
// on launch.
import 'dart:convert';
import 'package:flutter/material.dart';
import '../platform/platform_bridge.dart';
import '../providers/notes_provider.dart';

/// Persistence key (also the on-disk file name on native platforms).
const String kSettingsKey = 'bellonotes_settings.json';

class AppSettings extends ChangeNotifier {
  Locale _locale = const Locale('en');
  ThemeMode _themeMode = ThemeMode.system;
  NotesSortOrder _sortOrder = NotesSortOrder.dateNewest;
  bool _sortByCreated = false;
  String _defaultFormat = 'body'; // title, heading, subheading, body
  int _defaultTextSize = 3; // 1-5
  bool _darkEditorBg = false;
  String? _lockPassword;
  int _seedColor = 0xFFF5A623; // app accent / theme preset

  Locale get locale => _locale;
  ThemeMode get themeMode => _themeMode;
  int get seedColorValue => _seedColor;
  Color get seedColor => Color(_seedColor);
  NotesSortOrder get sortOrder => _sortOrder;
  bool get sortByCreated => _sortByCreated;
  String get defaultFormat => _defaultFormat;
  int get defaultTextSize => _defaultTextSize;
  bool get darkEditorBg => _darkEditorBg;
  String? get lockPassword => _lockPassword;

  /// Base font size for the editor body text, derived from the 1–5 setting.
  double get editorFontSize => const [14.0, 15.0, 16.0, 18.0, 20.0][
      (_defaultTextSize - 1).clamp(0, 4)];

  late final Future<void> loaded;

  AppSettings() {
    loaded = _load();
  }

  Future<void> _load() async {
    try {
      final raw = await readLocal(kSettingsKey);
      if (raw != null && raw.isNotEmpty) {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final loc = json['locale'] as String?;
        if (loc != null) _locale = Locale(loc);
        final theme = json['theme'] as String?;
        if (theme == 'light') _themeMode = ThemeMode.light;
        if (theme == 'dark') _themeMode = ThemeMode.dark;
        final sort = json['sort'] as String?;
        if (sort != null) {
          _sortOrder = NotesSortOrder.values.firstWhere(
            (e) => e.name == sort,
            orElse: () => NotesSortOrder.dateNewest,
          );
        }
        _sortByCreated = json['sort_by_created'] == true;
        _defaultFormat = (json['default_format'] as String?) ?? 'body';
        _defaultTextSize = (json['default_text_size'] as int?) ?? 3;
        _darkEditorBg = json['dark_editor_bg'] == true;
        _lockPassword = json['lock_password'] as String?;
        _seedColor = (json['seed_color'] as int?) ?? _seedColor;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      await writeLocal(kSettingsKey, jsonEncode({
        'locale': _locale.languageCode,
        'theme': _themeMode == ThemeMode.light
            ? 'light'
            : _themeMode == ThemeMode.dark
                ? 'dark'
                : 'system',
        'sort': _sortOrder.name,
        'sort_by_created': _sortByCreated,
        'default_format': _defaultFormat,
        'default_text_size': _defaultTextSize,
        'dark_editor_bg': _darkEditorBg,
        'lock_password': _lockPassword,
        'seed_color': _seedColor,
      }));
    } catch (_) {}
  }

  void setLocale(Locale locale) { _locale = locale; notifyListeners(); _save(); }
  void setThemeMode(ThemeMode mode) { _themeMode = mode; notifyListeners(); _save(); }
  void setSortOrder(NotesSortOrder o) { _sortOrder = o; notifyListeners(); _save(); }
  void setSortByCreated(bool v) { _sortByCreated = v; notifyListeners(); _save(); }
  void setDefaultFormat(String v) { _defaultFormat = v; notifyListeners(); _save(); }
  void setDefaultTextSize(int v) { _defaultTextSize = v; notifyListeners(); _save(); }
  void setDarkEditorBg(bool v) { _darkEditorBg = v; notifyListeners(); _save(); }
  void setLockPassword(String? v) { _lockPassword = v; notifyListeners(); _save(); }
  void setSeedColor(int v) { _seedColor = v; notifyListeners(); _save(); }

  String t(String en, {String? fr, String? ar, String? zh, String? it, String? es}) {
    switch (_locale.languageCode) {
      case 'fr': return fr ?? en;
      case 'ar': return ar ?? en;
      case 'zh': return zh ?? en;
      case 'it': return it ?? en;
      case 'es': return es ?? en;
      default: return en;
    }
  }
}
