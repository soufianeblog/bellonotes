// Native (`dart:io`) implementation of the platform bridge — desktop & mobile.
// See platform_bridge.dart for the contract; the web counterpart lives in
// platform_bridge_web.dart and must keep the same public signatures.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite/sqflite.dart' as sqf;
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import 'picked_file.dart';

// Re-export the pure-Dart sqflite API so shared code (database_service) gets the
// shared types from the bridge without importing an io-only package directly.
export 'package:sqflite_common/sqlite_api.dart'
    show Database, OpenDatabaseOptions, ConflictAlgorithm, Transaction;

const _uuid = Uuid();
bool _ffiInitialized = false;

bool get isWebPlatform => false;

// ─── Database ───

Future<Database> openAppDatabase(OpenDatabaseOptions options) async {
  final dir = await getApplicationDocumentsDirectory();
  final dbPath = p.join(dir.path, 'bellonotes.db');
  if (defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    // Desktop: bundled native SQLite via FFI. We open through the FFI factory
    // directly rather than overriding the global one (avoids sqflite's noisy
    // "changing default factory" warning on every launch).
    if (!_ffiInitialized) {
      sqfliteFfiInit();
      _ffiInitialized = true;
    }
    return databaseFactoryFfi.openDatabase(dbPath, options: options);
  }
  // Mobile (Android/iOS): the default plugin-backed factory.
  return sqf.databaseFactory.openDatabase(dbPath, options: options);
}

// ─── Local key/value store (a JSON file per key in the documents dir) ───

Future<File> _localFile(String key) async {
  final dir = await getApplicationDocumentsDirectory();
  return File(p.join(dir.path, key));
}

Future<String?> readLocal(String key) async {
  try {
    final f = await _localFile(key);
    if (await f.exists()) return await f.readAsString();
  } catch (_) {}
  return null;
}

Future<void> writeLocal(String key, String value) async {
  try {
    final f = await _localFile(key);
    await f.writeAsString(value);
  } catch (_) {}
}

// ─── File save / pick ───

/// Saves [bytes] to a user-chosen location. Returns true if written.
Future<bool> saveBytes(String fileName, Uint8List bytes,
    {List<String>? extensions}) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Save',
    fileName: fileName,
    type: extensions != null ? FileType.custom : FileType.any,
    allowedExtensions: extensions,
  );
  if (path == null) return false;
  var dest = path;
  if (extensions != null &&
      extensions.isNotEmpty &&
      !extensions.any((e) => dest.toLowerCase().endsWith('.$e'))) {
    dest = '$dest.${extensions.first}';
  }
  await File(dest).writeAsBytes(bytes);
  return true;
}

Future<bool> saveText(String fileName, String text,
        {List<String>? extensions}) =>
    saveBytes(fileName, Uint8List.fromList(utf8.encode(text)),
        extensions: extensions);

/// Prompts the user to pick a file and returns its bytes.
Future<PickedFile?> pickBytes({List<String>? extensions}) async {
  final res = await FilePicker.platform.pickFiles(
    type: extensions != null ? FileType.custom : FileType.any,
    allowedExtensions: extensions,
    withData: true,
  );
  if (res == null) return null;
  final f = res.files.single;
  var data = f.bytes;
  if (data == null && f.path != null) {
    data = await File(f.path!).readAsBytes();
  }
  if (data == null) return null;
  return PickedFile(f.name, data);
}

/// Picks an image and returns a reference the editor can store & render. On
/// native this is the absolute file path.
Future<String?> pickImageRef() async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.image,
    allowMultiple: false,
  );
  return res?.files.single.path;
}

// ─── Import/export image helpers ───

/// Reads the bytes of a locally-referenced file (image attachment). Returns
/// null if it can't be read.
Future<Uint8List?> readFileBytes(String path) async {
  try {
    return await File(path).readAsBytes();
  } catch (_) {
    return null;
  }
}

/// Persists an image extracted from an import archive and returns the reference
/// to store in note content. On native this writes to the images directory and
/// returns the absolute path.
Future<String> persistImportedImage(String baseName, Uint8List bytes) async {
  final dir = await getApplicationDocumentsDirectory();
  final imagesDir = Directory(p.join(dir.path, 'bellonotes_images'));
  if (!await imagesDir.exists()) await imagesDir.create(recursive: true);
  final dest = p.join(imagesDir.path, '${_uuid.v4()}_$baseName');
  await File(dest).writeAsBytes(bytes);
  return dest;
}

// ─── Image rendering for a local file path ───

Widget buildFileImage(String path,
    {Key? imageKey,
    double? width,
    BoxFit? fit,
    Widget Function(BuildContext)? errorBuilder}) {
  return Image.file(
    File(path),
    key: imageKey,
    width: width,
    fit: fit,
    errorBuilder: errorBuilder == null
        ? null
        : (context, _, _) => errorBuilder(context),
  );
}

// ─── Log file output ───

File? _logFile;
bool _logResolved = false;

Future<void> _ensureLogFile() async {
  if (_logResolved) return;
  _logResolved = true;
  try {
    final dir = await getApplicationDocumentsDirectory();
    _logFile = File(p.join(dir.path, 'bellonotes_errors.log'));
  } catch (_) {}
}

Future<void> appendLog(String line) async {
  await _ensureLogFile();
  try {
    await _logFile?.writeAsString(line, mode: FileMode.append, flush: false);
  } catch (_) {}
}

Future<void> clearLog() async {
  await _ensureLogFile();
  try {
    if (_logFile != null && await _logFile!.exists()) {
      await _logFile!.writeAsString('');
    }
  } catch (_) {}
}
