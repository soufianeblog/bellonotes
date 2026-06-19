import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../models/note.dart';
import '../models/folder.dart';
import 'database_service.dart';
import 'error_logger.dart';

/// Handles exporting and importing the full app dataset as a single .zip
/// archive. The archive layout is:
///
///   manifest.json   – metadata + schema version
///   folders.json    – list of folder maps
///   notes.json      – list of note maps (image paths rewritten to relative)
///   settings.json   – raw settings file (if present)
///   `images/<file>` – any image attachments referenced by notes
class DataTransferService {
  // v2: image embeds may carry a JSON object ({"path","width","link"}) instead
  // of a bare path string; table embeds carry per-cell formatting & borders.
  // Both are handled transparently on export/import.
  static const int schemaVersion = 2;
  static const _uuid = Uuid();

  // ─── EXPORT ───

  /// Builds the archive and writes it to [destinationPath]. Returns the number
  /// of notes exported.
  static Future<int> exportToZip(String destinationPath) async {
    final folders = await DatabaseService.getAllFoldersRaw();
    final notes = await DatabaseService.getAllNotesRaw();
    final encoder = ZipFileEncoder();
    encoder.create(destinationPath);
    try {
      // Collect & rewrite image references so the archive is self-contained.
      final imageEntries = <String, String>{}; // absolutePath -> archiveName
      final exportedNotes = <Map<String, dynamic>>[];
      for (final note in notes) {
        final rewritten =
            _rewriteImagePaths(note.content, imageEntries, toArchive: true);
        final map = note.toMap();
        map['content'] = rewritten;
        exportedNotes.add(map);
      }

      _addJson(encoder, 'manifest.json', {
        'app': 'bellonotes',
        'schema_version': schemaVersion,
        'exported_at': DateTime.now().toIso8601String(),
        'note_count': notes.length,
        'folder_count': folders.length,
      });
      _addJson(
          encoder, 'folders.json', folders.map((f) => f.toMap()).toList());
      _addJson(encoder, 'notes.json', exportedNotes);

      // Settings file (best effort).
      try {
        final dir = await getApplicationDocumentsDirectory();
        final settingsFile =
            File(p.join(dir.path, 'bellonotes_settings.json'));
        if (await settingsFile.exists()) {
          await encoder.addFile(settingsFile, 'settings.json');
        }
      } catch (e, s) {
        ErrorLogger.instance
            .warn('Export: settings not included', details: '$e\n$s');
      }

      // Image attachments.
      for (final entry in imageEntries.entries) {
        final file = File(entry.key);
        if (await file.exists()) {
          await encoder.addFile(file, entry.value);
        }
      }

      return notes.length;
    } finally {
      await encoder.close();
    }
  }

  static void _addJson(ZipFileEncoder encoder, String name, Object data) {
    final bytes = utf8.encode(const JsonEncoder.withIndent('  ').convert(data));
    encoder.addArchiveFile(ArchiveFile(name, bytes.length, bytes));
  }

  // ─── IMPORT ───

  /// Reads an archive from [sourcePath] and merges its contents into the
  /// database (rows with matching ids are replaced). Returns note count.
  static Future<int> importFromZip(String sourcePath) async {
    final bytes = await File(sourcePath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 1. Restore image attachments to a stable directory.
    final imagesDir = await _imagesDirectory();
    final extractedImages = <String, String>{}; // archiveName -> absolutePath
    for (final file in archive.files) {
      if (!file.isFile) continue;
      if (file.name.startsWith('images/')) {
        final base = p.basename(file.name);
        final dest = p.join(imagesDir.path, base);
        await File(dest).writeAsBytes(file.content as List<int>);
        extractedImages[file.name] = dest;
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

  static Future<Directory> _imagesDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(p.join(dir.path, 'bellonotes_images'));
    if (!await imagesDir.exists()) await imagesDir.create(recursive: true);
    return imagesDir;
  }

  /// Rewrites image paths embedded in a note's Delta JSON.
  ///
  /// When [toArchive] is true, absolute file paths are replaced with
  /// `images/<name>` relative references and recorded in [mapping]
  /// (absolutePath -> archiveName). When false, relative `images/<name>`
  /// references are replaced with the absolute extracted path looked up in
  /// [mapping] (archiveName -> absolutePath).
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

  /// Maps a single image path between absolute and archive-relative forms.
  /// Returns the new value, or null when no rewrite is needed.
  static String? _mapImagePath(
      String path, Map<String, String> mapping, bool toArchive) {
    if (toArchive) {
      if (path.startsWith('images/')) return null;
      return mapping.putIfAbsent(
          path, () => 'images/${_uuid.v4()}_${p.basename(path)}');
    }
    return mapping[path];
  }
}
