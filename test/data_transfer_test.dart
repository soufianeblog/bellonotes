import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:bellonotes/models/note.dart';
import 'package:bellonotes/models/folder.dart';
import 'package:bellonotes/services/database_service.dart';
import 'package:bellonotes/services/data_transfer_service.dart';
import 'test_helpers.dart';

void main() {
  setUp(() async {
    await initTestEnvironment();
    await deleteDbFile();
    await DatabaseService.resetForTests();
  });

  tearDown(() async {
    await DatabaseService.resetForTests();
    await cleanupTestEnvironment();
  });

  test('export then import restores notes and folders', () async {
    await DatabaseService.insertFolder(
        Folder(id: 'f1', name: 'Work', createdAt: DateTime(2024)));
    await DatabaseService.insertNote(Note(
      id: 'n1',
      title: 'Hello',
      content: 'Hello body',
      folderIds: ['f1'],
      createdAt: DateTime(2024),
      modifiedAt: DateTime(2024),
    ));

    final zipPath = p.join(testTempDir.path, 'backup.zip');
    final exported = await DataTransferService.exportToZip(zipPath);
    expect(exported, 1);
    expect(await File(zipPath).exists(), isTrue);

    // Wipe everything by permanently deleting, then re-import.
    await DatabaseService.permanentlyDeleteNote('n1');
    await DatabaseService.permanentlyDeleteFolder('f1');
    expect((await DatabaseService.getAllNotesRaw()), isEmpty);

    final imported = await DataTransferService.importFromZip(zipPath);
    expect(imported, 1);
    final notes = await DatabaseService.getAllNotesRaw();
    final folders = await DatabaseService.getAllFoldersRaw();
    expect(notes.length, 1);
    expect(notes.first.title, 'Hello');
    expect(notes.first.folderIds, ['f1']);
    expect(folders.length, 1);
    expect(folders.first.name, 'Work');
  });

  test('image attachments are bundled and rewritten on round-trip', () async {
    // Create a fake image file referenced by a note's delta.
    final imgPath = p.join(testTempDir.path, 'pic.png');
    await File(imgPath).writeAsBytes([1, 2, 3, 4]);

    final delta = jsonEncode([
      {'insert': 'see image\n'},
      {
        'insert': {'image': imgPath}
      },
    ]);
    await DatabaseService.insertNote(Note(
      id: 'n1',
      content: delta,
      createdAt: DateTime(2024),
      modifiedAt: DateTime(2024),
    ));

    final zipPath = p.join(testTempDir.path, 'backup.zip');
    await DataTransferService.exportToZip(zipPath);

    // Remove original note + source image to simulate a fresh machine.
    await DatabaseService.permanentlyDeleteNote('n1');
    await File(imgPath).delete();

    await DataTransferService.importFromZip(zipPath);
    final note = (await DatabaseService.getAllNotesRaw()).first;
    final ops = jsonDecode(note.content) as List;
    final imageOp = ops.firstWhere((o) => o['insert'] is Map);
    final newPath = imageOp['insert']['image'] as String;

    // The rewritten path must point to an existing extracted file.
    expect(newPath, isNot(equals(imgPath)));
    expect(await File(newPath).exists(), isTrue);
    expect(await File(newPath).readAsBytes(), [1, 2, 3, 4]);
  });

  test('JSON image embeds (width/link) survive a round-trip', () async {
    final imgPath = p.join(testTempDir.path, 'pic2.png');
    await File(imgPath).writeAsBytes([5, 6, 7, 8]);

    // New-style image embed: a JSON object carrying path + width + link.
    final delta = jsonEncode([
      {'insert': 'pic\n'},
      {
        'insert': {
          'image': jsonEncode(
              {'path': imgPath, 'width': 400, 'link': 'https://example.com'})
        }
      },
    ]);
    await DatabaseService.insertNote(Note(
      id: 'n1',
      content: delta,
      createdAt: DateTime(2024),
      modifiedAt: DateTime(2024),
    ));

    final zipPath = p.join(testTempDir.path, 'backup.zip');
    await DataTransferService.exportToZip(zipPath);
    await DatabaseService.permanentlyDeleteNote('n1');
    await File(imgPath).delete();
    await DataTransferService.importFromZip(zipPath);

    final note = (await DatabaseService.getAllNotesRaw()).first;
    final ops = jsonDecode(note.content) as List;
    final imageOp = ops.firstWhere((o) => o['insert'] is Map);
    final embed =
        jsonDecode(imageOp['insert']['image'] as String) as Map<String, dynamic>;

    // Path rewritten to an extracted file; width & link preserved.
    expect(embed['path'], isNot(equals(imgPath)));
    expect(await File(embed['path'] as String).exists(), isTrue);
    expect(await File(embed['path'] as String).readAsBytes(), [5, 6, 7, 8]);
    expect(embed['width'], 400);
    expect(embed['link'], 'https://example.com');
  });

  test('importing missing file throws but does not corrupt db', () async {
    await DatabaseService.insertNote(Note(
      id: 'keep',
      content: 'keep me',
      createdAt: DateTime(2024),
      modifiedAt: DateTime(2024),
    ));
    await expectLater(
      DataTransferService.importFromZip(
          p.join(testTempDir.path, 'does_not_exist.zip')),
      throwsA(anything),
    );
    expect((await DatabaseService.getAllNotesRaw()).length, 1);
  });
}
