import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import '../models/folder.dart';
import '../platform/platform_bridge.dart';
import '../providers/app_settings.dart' show kSettingsKey;
import 'database_service.dart';
import 'error_logger.dart';

/// Handles exporting and importing the full app dataset as a single .zip
/// archive (held in memory as bytes, so it works identically on native and the
/// web). The archive layout is:
///
///   manifest.json   – metadata + schema version
///   folders.json    – list of folder maps
///   notes.json      – list of note maps (file-path images rewritten to
///                     relative `images/<file>`; `data:` URL images stay inline)
///   settings.json   – raw settings JSON (if present)
///   `images/<file>` – any file-backed image attachments referenced by notes
class DataTransferService {
  // v2: image embeds may carry a JSON object ({"path","width","link"}) instead
  // of a bare path string; table embeds carry per-cell formatting & borders.
  // Both are handled transparently on export/import.
  static const int schemaVersion = 2;
  static const _uuid = Uuid();

  // ─── EXPORT ───

  /// Builds the archive in memory and returns its bytes. [outNoteCount], when
  /// provided, is populated with the number of notes exported.
  static Future<Uint8List> exportToBytes({void Function(int)? outNoteCount}) async {
    final folders = await DatabaseService.getAllFoldersRaw();
    final notes = await DatabaseService.getAllNotesRaw();
    final archive = Archive();

    // Collect & rewrite file-path image references so the archive is
    // self-contained. `data:` URL images (web) are left inline in the content.
    final imageEntries = <String, String>{}; // sourceRef -> archiveName
    final exportedNotes = <Map<String, dynamic>>[];
    for (final note in notes) {
      final rewritten =
          _rewriteImagePaths(note.content, imageEntries, toArchive: true);
      final map = note.toMap();
      map['content'] = rewritten;
      exportedNotes.add(map);
    }

    _addJson(archive, 'manifest.json', {
      'app': 'bellonotes',
      'schema_version': schemaVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'note_count': notes.length,
      'folder_count': folders.length,
    });
    _addJson(archive, 'folders.json', folders.map((f) => f.toMap()).toList());
    _addJson(archive, 'notes.json', exportedNotes);

    // Settings (best effort).
    try {
      final settingsJson = await readLocal(kSettingsKey);
      if (settingsJson != null && settingsJson.isNotEmpty) {
        final bytes = utf8.encode(settingsJson);
        archive.addFile(ArchiveFile('settings.json', bytes.length, bytes));
      }
    } catch (e, s) {
      ErrorLogger.instance
          .warn('Export: settings not included', details: '$e\n$s');
    }

    // Image attachments (file-backed references only).
    for (final entry in imageEntries.entries) {
      final bytes = await readFileBytes(entry.key);
      if (bytes != null) {
        archive.addFile(ArchiveFile(entry.value, bytes.length, bytes));
      }
    }

    outNoteCount?.call(notes.length);
    final encoded = ZipEncoder().encode(archive);
    return Uint8List.fromList(encoded);
  }

  static void _addJson(Archive archive, String name, Object data) {
    final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(data));
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }

  // ─── IMPORT ───

  /// Reads an archive from [bytes] and merges its contents into the database
  /// (rows with matching ids are replaced). Returns note count.
  static Future<int> importFromBytes(Uint8List bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);

    // 1. Restore image attachments. On native they're written to the images
    //    directory (ref = path); on the web they become inline `data:` URLs.
    final extractedImages = <String, String>{}; // archiveName -> ref
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (file.name.startsWith('images/')) {
        final base = p.basename(file.name);
        final ref = await persistImportedImage(
            base, Uint8List.fromList(file.content as List<int>));
        extractedImages[file.name] = ref;
      }
    }

    // 2. Parse folders & notes.
    final foldersJson = _readJson(archive, 'folders.json');
    final notesJson = _readJson(archive, 'notes.json');

    final folders = <Folder>[];
    if (foldersJson is List) {
      for (final m in foldersJson) {
        if (m is Map) folders.add(Folder.fromMap(Map<String, dynamic>.from(m)));
      }
    }

    final notes = <Note>[];
    if (notesJson is List) {
      for (final m in notesJson) {
        if (m is! Map) continue;
        final map = Map<String, dynamic>.from(m);
        map['content'] = _rewriteImagePaths(
          (map['content'] as String?) ?? '',
          extractedImages,
          toArchive: false,
        );
        notes.add(Note.fromMap(map));
      }
    }

    await DatabaseService.importData(folders, notes);
    return notes.length;
  }

  static dynamic _readJson(Archive archive, String name) {
    for (final file in archive.files) {
      if (file.name == name && file.isFile) {
        try {
          return jsonDecode(utf8.decode(file.content as List<int>));
        } catch (e, s) {
          ErrorLogger.instance.error('Import: bad JSON in $name',
              details: '$e\n$s');
          return null;
        }
      }
    }
    return null;
  }

  /// Rewrites image references embedded in a note's Delta JSON.
  ///
  /// When [toArchive] is true, file-path references are replaced with
  /// `images/<name>` relative references and recorded in [mapping]
  /// (sourceRef -> archiveName). When false, relative `images/<name>`
  /// references are replaced with the stored reference looked up in [mapping]
  /// (archiveName -> ref). Inline `data:`/`http` URLs are never rewritten.
  static String _rewriteImagePaths(
    String content,
    Map<String, String> mapping, {
    required bool toArchive,
  }) {
    if (content.isEmpty) return content;
    dynamic decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      return content; // plain text / markdown — nothing to rewrite
    }
    if (decoded is! List) return content;

    var changed = false;
    for (final op in decoded) {
      if (op is Map && op['insert'] is Map) {
        final insert = op['insert'] as Map;
        final image = insert['image'];
        if (image is! String || image.isEmpty) continue;
        // Image embeds may be a bare path (legacy) or a JSON object
        // {"path":..., "width":..., "link":...}. Rewrite the path either way.
        if (image.trimLeft().startsWith('{')) {
          try {
            final m = jsonDecode(image) as Map<String, dynamic>;
            final path = m['path'] as String?;
            if (path != null && path.isNotEmpty) {
              final mapped = _mapImagePath(path, mapping, toArchive);
              if (mapped != null) {
                m['path'] = mapped;
                insert['image'] = jsonEncode(m);
                changed = true;
              }
            }
            continue;
          } catch (_) {
            // Not valid JSON after all — fall through to bare-path handling.
          }
        }
        final mapped = _mapImagePath(image, mapping, toArchive);
        if (mapped != null) {
          insert['image'] = mapped;
          changed = true;
        }
      }
    }
    return changed ? jsonEncode(decoded) : content;
  }

  /// Maps a single image reference between source and archive-relative forms.
  /// Returns the new value, or null when no rewrite is needed.
  static String? _mapImagePath(
      String ref, Map<String, String> mapping, bool toArchive) {
    if (toArchive) {
      // Already relative, or an inline URL that travels with the content.
      if (ref.startsWith('images/') ||
          ref.startsWith('data:') ||
          ref.startsWith('http')) {
        return null;
      }
      return mapping.putIfAbsent(
          ref, () => 'images/${_uuid.v4()}_${p.basename(ref)}');
    }
    return mapping[ref];
  }
}
