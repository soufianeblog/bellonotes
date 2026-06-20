// Web implementation of the platform bridge. Storage uses an IndexedDB-backed
// SQLite (sqflite_common_ffi_web); persistence uses localStorage; file save/
// pick use a browser download / the file picker's in-memory bytes; images are
// stored inline as `data:` URLs. See platform_bridge.dart for the contract.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:file_picker/file_picker.dart';
import 'package:web/web.dart' as web;
import 'picked_file.dart';

export 'package:sqflite_common/sqlite_api.dart'
    show Database, OpenDatabaseOptions, ConflictAlgorithm, Transaction;

bool get isWebPlatform => true;

// ─── Database (IndexedDB-backed SQLite via a shared web worker) ───

Future<Database> openAppDatabase(OpenDatabaseOptions options) {
  return databaseFactoryFfiWeb.openDatabase('bellonotes.db', options: options);
}

// ─── Local key/value store (browser localStorage) ───

Future<String?> readLocal(String key) async {
  return web.window.localStorage.getItem(key);
}

Future<void> writeLocal(String key, String value) async {
  web.window.localStorage.setItem(key, value);
}

// ─── File save / pick ───

/// Triggers a browser download of [bytes] under [fileName].
Future<bool> saveBytes(String fileName, Uint8List bytes,
    {List<String>? extensions}) async {
  final parts = <JSAny>[bytes.toJS].toJS;
  final blob =
      web.Blob(parts, web.BlobPropertyBag(type: 'application/octet-stream'));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return true;
}

Future<bool> saveText(String fileName, String text,
        {List<String>? extensions}) =>
    saveBytes(fileName, Uint8List.fromList(utf8.encode(text)),
        extensions: extensions);

Future<PickedFile?> pickBytes({List<String>? extensions}) async {
  final res = await FilePicker.platform.pickFiles(
    type: extensions != null ? FileType.custom : FileType.any,
    allowedExtensions: extensions,
    withData: true,
  );
  if (res == null) return null;
  final f = res.files.single;
  final data = f.bytes;
  if (data == null) return null;
  return PickedFile(f.name, data);
}

/// Picks an image and returns a `data:` URL so it can be stored inline in the
/// note (the web has no persistent file paths).
Future<String?> pickImageRef() async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.image,
    allowMultiple: false,
    withData: true,
  );
  if (res == null) return null;
  final f = res.files.single;
  final data = f.bytes;
  if (data == null) return null;
  return 'data:${mimeFromFileName(f.name)};base64,${base64Encode(data)}';
}

// ─── Import/export image helpers ───

/// No locally-referenced files exist on the web.
Future<Uint8List?> readFileBytes(String path) async => null;

/// Imported images become inline `data:` URLs on the web.
Future<String> persistImportedImage(String baseName, Uint8List bytes) async {
  return 'data:${mimeFromFileName(baseName)};base64,${base64Encode(bytes)}';
}

// ─── Image rendering for a (legacy) local file path ───
//
// New web images are stored as `data:` URLs and rendered by the shared code via
// Image.memory; a bare file path can only come from a native export, so show a
// placeholder rather than failing to compile against `dart:io`.
Widget buildFileImage(String path,
    {Key? imageKey,
    double? width,
    BoxFit? fit,
    Widget Function(BuildContext)? errorBuilder}) {
  return Builder(
    key: imageKey,
    builder: (context) =>
        errorBuilder?.call(context) ??
        Container(
          height: 100,
          width: width,
          color: Colors.grey.shade200,
          child: const Center(child: Icon(Icons.broken_image, size: 32)),
        ),
  );
}

// ─── Log output (in-memory only on web) ───

Future<void> appendLog(String line) async {}

Future<void> clearLog() async {}
