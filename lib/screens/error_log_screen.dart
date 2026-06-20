// Diagnostics screen that displays the in-memory error/warn/info log captured
// by [ErrorLogger], with copy-to-clipboard and export-to-file actions. Reached
// from Settings → Diagnostics.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/error_logger.dart';
import '../platform/platform_bridge.dart' as platform;
import '../utils/desktop_chrome.dart';
import '../l10n/strings.dart';

class ErrorLogScreen extends StatefulWidget {
  const ErrorLogScreen({super.key});

  @override
  State<ErrorLogScreen> createState() => _ErrorLogScreenState();
}

class _ErrorLogScreenState extends State<ErrorLogScreen> {
  @override
  void initState() {
    super.initState();
    ErrorLogger.instance.revision.addListener(_onChange);
  }

  @override
  void dispose() {
    ErrorLogger.instance.revision.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  Color _levelColor(BuildContext context, String level) {
    switch (level) {
      case 'ERROR':
        return Theme.of(context).colorScheme.error;
      case 'WARN':
        return Colors.orange;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final entries = ErrorLogger.instance.entries.reversed.toList();
    final isDesktop = isDesktopChrome;

    return Scaffold(
      appBar: isDesktop
          ? null
          : AppBar(
              title: Text(s.errorLog),
              actions: _actions(context, s),
            ),
      body: Column(children: [
        if (isDesktop)
          Container(
            height: 44,
            padding: const EdgeInsets.only(left: 78, right: 8),
            color: Theme.of(context).colorScheme.surfaceContainerLowest,
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, size: 16),
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              Text(s.errorLog,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              ..._actions(context, s),
            ]),
          ),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text('—',
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant)),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        e.level == 'ERROR'
                            ? Icons.error_outline
                            : e.level == 'WARN'
                                ? Icons.warning_amber_outlined
                                : Icons.info_outline,
                        color: _levelColor(context, e.level),
                        size: 18,
                      ),
                      title: Text(e.message,
                          style: const TextStyle(fontSize: 13)),
                      subtitle: Text(
                        '${e.time.toIso8601String()}'
                        '${e.details != null ? '\n${e.details}' : ''}',
                        style: const TextStyle(
                            fontSize: 11, fontFamily: 'monospace'),
                      ),
                      isThreeLine: e.details != null,
                    );
                  },
                ),
        ),
      ]),
    );
  }

  Future<void> _exportLogs(BuildContext context, S s) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final saved = await platform.saveText(
        'bellonotes_logs_$ts.txt',
        ErrorLogger.instance.exportText(),
        extensions: ['txt'],
      );
      if (!saved) return;
      messenger.showSnackBar(SnackBar(content: Text(s.exportLogs)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  List<Widget> _actions(BuildContext context, S s) {
    return [
      IconButton(
        icon: const Icon(Icons.copy, size: 18),
        tooltip: 'Copy',
        onPressed: () {
          Clipboard.setData(
              ClipboardData(text: ErrorLogger.instance.exportText()));
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Copied')));
        },
      ),
      IconButton(
        icon: const Icon(Icons.save_alt, size: 18),
        tooltip: s.exportLogs,
        onPressed: () => _exportLogs(context, s),
      ),
      IconButton(
        icon: const Icon(Icons.delete_outline, size: 18),
        tooltip: s.delete,
        onPressed: () => ErrorLogger.instance.clear(),
      ),
    ];
  }
}
