import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A path_provider mock that returns a per-test temporary directory so the
/// database, settings and exported files all live in an isolated sandbox.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  final String dir;
  _FakePathProvider(this.dir);

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
  @override
  Future<String?> getApplicationSupportPath() async => dir;
  @override
  Future<String?> getTemporaryPath() async => dir;
  @override
  Future<String?> getDownloadsPath() async => dir;
}

late Directory testTempDir;

/// Call inside `setUp`. Creates a fresh temp dir + in-memory sqflite factory
/// and resets DatabaseService's static state so each test is isolated.
Future<void> initTestEnvironment() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  testTempDir =
      await Directory.systemTemp.createTemp('bellonotes_test_');
  PathProviderPlatform.instance = _FakePathProvider(testTempDir.path);
}

Future<void> cleanupTestEnvironment() async {
  try {
    if (await testTempDir.exists()) {
      await testTempDir.delete(recursive: true);
    }
  } catch (_) {}
}

/// Removes the on-disk database file so the next test starts empty. Must be
/// called before the first DatabaseService access in a test if reuse is a risk.
Future<void> deleteDbFile() async {
  final f = File(p.join(testTempDir.path, 'bellonotes.db'));
  if (await f.exists()) await f.delete();
}
