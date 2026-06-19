// Application entry point. Installs the global error guard, initializes
// locale data, wires up the provider-based state (settings, notes, folders),
// configures theming and localization, and shows [HomeScreen].
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'providers/notes_provider.dart';
import 'providers/folders_provider.dart';
import 'providers/app_settings.dart';
import 'services/error_logger.dart';
import 'screens/home_screen.dart';

void main() {
  runGuardedApp(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await ErrorLogger.instance.init();
    ErrorLogger.instance.install();
    await initializeDateFormatting();

    final appSettings = AppSettings();
    final notesProvider = NotesProvider();
    final foldersProvider = FoldersProvider();

    // Wait for settings to load from disk before applying sort, etc.
    await appSettings.loaded;
    await foldersProvider.loadFolders();
    notesProvider.setInitialSort(appSettings.sortOrder);
    notesProvider.onSortChanged = (order) => appSettings.setSortOrder(order);
    await notesProvider.loadNotes();

    notesProvider.onFoldersNeedRefresh = () => foldersProvider.refreshCounts();

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: notesProvider),
          ChangeNotifierProvider.value(value: foldersProvider),
          ChangeNotifierProvider.value(value: appSettings),
        ],
        child: const BellonotesApp(),
      ),
    );
  });
}

class BellonotesApp extends StatelessWidget {
  const BellonotesApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettings>();

    return MaterialApp(
      title: 'Bello Notes',
      debugShowCheckedModeBanner: false,
      locale: settings.locale,
      supportedLocales: const [
        Locale('en'),
        Locale('fr'),
        Locale('ar'),
        Locale('zh'),
        Locale('it'),
        Locale('es'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: settings.seedColor,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: settings.seedColor,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: settings.themeMode,
      home: const HomeScreen(),
    );
  }
}
