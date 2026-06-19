import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:bellonotes/providers/notes_provider.dart';
import 'package:bellonotes/providers/folders_provider.dart';
import 'package:bellonotes/providers/app_settings.dart';
import 'package:bellonotes/services/database_service.dart';
import 'package:bellonotes/screens/home_screen.dart';
import 'test_helpers.dart';

// Verifies the adaptive HomeScreen chrome at the three width bands when running
// as a *mobile* (Android) target: every band must expose an AppBar so the
// folder drawer and "new note" remain reachable and content clears the status
// bar. A single pump() is used because HomeScreen embeds the flutter_quill
// editor, whose tickers never settle under flutter_test.

Future<Widget> _buildHome(WidgetTester tester) async {
  late NotesProvider notes;
  late FoldersProvider folders;
  late AppSettings settings;
  await tester.runAsync(() async {
    settings = AppSettings();
    await settings.loaded;
    notes = NotesProvider();
    folders = FoldersProvider();
    await folders.loadFolders();
    await notes.loadNotes();
  });
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: notes),
      ChangeNotifierProvider.value(value: folders),
      ChangeNotifierProvider.value(value: settings),
    ],
    child: const MaterialApp(
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: HomeScreen(),
    ),
  );
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

  // Sets the target platform to Android for the duration of one test. The
  // override must be cleared inside the test body — the test binding asserts it
  // is unset before per-test teardown runs.
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final app = await _buildHome(tester);
    await tester.pumpWidget(app);
    await tester.pump();
  }

  testWidgets('mobile width (<600) shows an AppBar with menu + add',
      (tester) async {
    await pumpAt(tester, const Size(400, 800));
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsOneWidget);
    expect(find.byIcon(Icons.add), findsWidgets);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('tablet width (600-900) on Android shows an AppBar (folders + new note reachable)',
      (tester) async {
    await pumpAt(tester, const Size(720, 900));
    // The regression we are guarding against: this band previously rendered no
    // AppBar/title bar on Android, leaving the drawer reachable only by swipe.
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byIcon(Icons.menu), findsOneWidget);
    expect(find.byType(Drawer), findsNothing); // closed until opened
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop width (>=900) on Android wraps content in SafeArea',
      (tester) async {
    await pumpAt(tester, const Size(1100, 900));
    // No custom window title bar on a mobile target, but content must be inset
    // below the status bar.
    expect(find.byType(SafeArea), findsWidgets);
    debugDefaultTargetPlatformOverride = null;
  });
}
