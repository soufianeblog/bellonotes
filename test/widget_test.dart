import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:bellonotes/providers/notes_provider.dart';
import 'package:bellonotes/providers/folders_provider.dart';
import 'package:bellonotes/providers/app_settings.dart';
import 'package:bellonotes/services/database_service.dart';
import 'package:bellonotes/widgets/folder_sidebar.dart';
import 'package:bellonotes/widgets/notes_sidebar.dart';
import 'test_helpers.dart';

// IMPORTANT: testWidgets runs inside a fake-async zone, so any real I/O
// (path_provider, sqflite, File) must be performed inside tester.runAsync(),
// otherwise the await never completes and the test hangs.
//
// We render the sidebars rather than the full HomeScreen — HomeScreen builds
// the flutter_quill editor whose tickers never settle under flutter_test.
// Provider/DB behaviour is covered by the other (real-async) test files.

class _Ctx {
  late NotesProvider notes;
  late FoldersProvider folders;
  late AppSettings settings;
  late Widget app;
}

Future<_Ctx> _build(WidgetTester tester, Widget child) async {
  final ctx = _Ctx();
  await tester.runAsync(() async {
    ctx.settings = AppSettings();
    await ctx.settings.loaded;
    ctx.notes = NotesProvider();
    ctx.folders = FoldersProvider();
    await ctx.folders.loadFolders();
    await ctx.notes.loadNotes();
    ctx.notes.onFoldersNeedRefresh = ctx.folders.refreshCounts;
  });
  ctx.app = MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: ctx.notes),
      ChangeNotifierProvider.value(value: ctx.folders),
      ChangeNotifierProvider.value(value: ctx.settings),
    ],
    child: MaterialApp(
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: SizedBox(width: 320, height: 640, child: child)),
    ),
  );
  return ctx;
}

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

  testWidgets('folder sidebar shows core sections', (tester) async {
    final ctx = await _build(tester, const FolderSidebar());
    await tester.pumpWidget(ctx.app);
    await tester.pump();

    expect(find.text('Folders'), findsWidgets);
    expect(find.text('All Notes'), findsOneWidget);
    expect(find.text('Trash'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('notes sidebar lists a created note by title', (tester) async {
    final ctx = await _build(tester, const NotesSidebar());
    await tester.pumpWidget(ctx.app);
    await tester.pump();

    await tester.runAsync(() async {
      final n = await ctx.notes.createNote();
      await ctx.notes.updateNoteContent(n, 'Buy groceries');
    });
    await tester.pump();

    expect(find.text('Buy groceries'), findsWidgets);
  });

  testWidgets('entering selection mode shows the action bar', (tester) async {
    final ctx = await _build(tester, const NotesSidebar());
    await tester.pumpWidget(ctx.app);
    await tester.pump();

    late String id;
    await tester.runAsync(() async {
      final n = await ctx.notes.createNote();
      await ctx.notes.updateNoteContent(n, 'Task one');
      id = n.id;
    });
    await tester.pump();

    ctx.notes.enterSelection(id);
    await tester.pump();

    expect(find.textContaining('selected'), findsOneWidget);
  });
}
