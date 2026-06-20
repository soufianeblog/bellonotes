import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import '../platform/platform_bridge.dart' as platform;

/// A single logged entry.
class LogEntry {
  final DateTime time;
  final String level; // ERROR, WARN, INFO
  final String message;
  final String? details;

  LogEntry(this.level, this.message, {this.details, DateTime? time})
      : time = time ?? DateTime.now();

  @override
  String toString() {
    final ts = time.toIso8601String();
    final base = '[$ts] $level: $message';
    return details != null && details!.isNotEmpty ? '$base\n$details' : base;
  }
}

/// Lightweight error/log facility. Keeps a rolling in-memory buffer and
/// appends to a log file on disk so issues can be reviewed later.
class ErrorLogger {
  ErrorLogger._();
  static final ErrorLogger instance = ErrorLogger._();

  static const int _maxEntries = 500;
  final ListQueue<LogEntry> _entries = ListQueue<LogEntry>();
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  bool _initialized = false;

  List<LogEntry> get entries => _entries.toList(growable: false);

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    // Native platforms append to a log file via the bridge; the web keeps the
    // in-memory buffer only. Nothing to set up here.
  }

  /// Installs global handlers so uncaught framework + zone errors are captured.
  void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      error(
        details.exceptionAsString(),
        details: details.stack?.toString(),
      );
      previous?.call(details);
    };
    PlatformDispatcher.instance.onError = (Object e, StackTrace stack) {
      error(e.toString(), details: stack.toString());
      return false;
    };
  }

  void error(String message, {String? details}) =>
      _add(LogEntry('ERROR', message, details: details));

  void warn(String message, {String? details}) =>
      _add(LogEntry('WARN', message, details: details));

  void info(String message, {String? details}) =>
      _add(LogEntry('INFO', message, details: details));

  void _add(LogEntry entry) {
    _entries.addLast(entry);
    while (_entries.length > _maxEntries) {
      _entries.removeFirst();
    }
    revision.value++;
    if (kDebugMode) {
      debugPrint(entry.toString());
    }
    _appendToFile(entry);
  }

  Future<void> _appendToFile(LogEntry entry) async {
    // Never let logging throw (the bridge swallows its own IO errors).
    await platform.appendLog('${entry.toString()}\n');
  }

  Future<void> clear() async {
    _entries.clear();
    revision.value++;
    await platform.clearLog();
  }

  String exportText() => _entries.map((e) => e.toString()).join('\n\n');
}

/// Runs [body] in a guarded zone so errors flow into [ErrorLogger].
void runGuardedApp(void Function() body) {
  runZonedGuarded(body, (error, stack) {
    ErrorLogger.instance.error(error.toString(), details: stack.toString());
  });
}
