import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/strings.dart';

/// Standalone "About" page for Bello Notes.
///
/// Structurally a sibling of [SettingsScreen]: on desktop/tablet it is rendered
/// embedded in the right-hand pane (with [onClose] wired to the parent so the
/// sidebars stay visible), and on mobile it is pushed as its own route. It
/// surfaces the app identity, author, and the project's public links (X,
/// website, source repository) for the open-source release.
class AboutScreen extends StatelessWidget {
  /// When provided, the page is embedded in the desktop right-pane and the
  /// title-bar button calls this instead of popping a route.
  final VoidCallback? onClose;

  const AboutScreen({super.key, this.onClose});

  /// The app version, kept in one place so the displayed value matches the
  /// `version:` field in `pubspec.yaml`.
  static const String appVersion = '1.0.0';

  // Public project links. Centralised here so the About page and any future
  // callers reference a single source of truth.
  static const String xHandle = 'soufianeblog';
  static const String xUrl = 'https://x.com/soufianeblog';
  static const String websiteUrl = 'https://bellocloud.com';
  static const String repoUrl = 'https://github.com/soufianeblog/bellonotes';
  static const String donateUrl = 'http://paypal.me/paysoufiane';

  /// Opens [url] in the platform's default browser, ignoring failures (a dead
  /// link should never crash the page).
  Future<void> _open(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final isDesktop = Platform.isMacOS || Platform.isWindows || Platform.isLinux;
    // Pushed as a standalone route on mobile (not embedded, not desktop): give
    // it a real AppBar so there's a back button.
    final isMobileRoute = !isDesktop && onClose == null;

    return Scaffold(
      appBar: isMobileRoute ? AppBar(title: Text(s.about)) : null,
      body: Column(
        children: [
          if (isDesktop || onClose != null) _buildTitleBar(context, s),
          Expanded(
            child: ListView(
              children: [
                const SizedBox(height: 24),
                // App icon, name, version and one-line tagline.
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Icon(Icons.sticky_note_2_outlined,
                            size: 38, color: theme.colorScheme.primary),
                      ),
                      const SizedBox(height: 14),
                      Text(s.appName,
                          style: theme.textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text('${s.version} $appVersion',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(s.aboutTagline,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                      ),
                      const SizedBox(height: 18),
                      // Support the project via PayPal.
                      FilledButton.icon(
                        onPressed: () => _open(donateUrl),
                        icon: const Text('❤️', style: TextStyle(fontSize: 16)),
                        label: const Text('Donate'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                const Divider(indent: 16, endIndent: 16),

                // Author — links to the X (Twitter) profile.
                ListTile(
                  leading: const Icon(Icons.alternate_email),
                  title: Text(s.madeBy),
                  subtitle: Text('@$xHandle'),
                  trailing: const Icon(Icons.open_in_new, size: 16),
                  onTap: () => _open(xUrl),
                ),
                // Product website.
                ListTile(
                  leading: const Icon(Icons.language),
                  title: Text(s.website),
                  subtitle: const Text('bellocloud.com'),
                  trailing: const Icon(Icons.open_in_new, size: 16),
                  onTap: () => _open(websiteUrl),
                ),
                // Public source repository.
                ListTile(
                  leading: const Icon(Icons.code),
                  title: Text(s.sourceCode),
                  subtitle: const Text('github.com/soufianeblog/bellonotes'),
                  trailing: const Icon(Icons.open_in_new, size: 16),
                  onTap: () => _open(repoUrl),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Compact title bar matching [SettingsScreen]: a close/back affordance plus
  /// the page title. In embedded mode the leading control closes the pane; as a
  /// pushed route it pops.
  Widget _buildTitleBar(BuildContext context, S s) {
    final theme = Theme.of(context);
    final embedded = onClose != null;
    // Only a full-window macOS title bar needs to clear the traffic lights; an
    // embedded pane (and Windows/Linux) does not.
    final leftPad = embedded ? 8.0 : (Platform.isMacOS ? 78.0 : 12.0);
    return Container(
      height: 38,
      padding: EdgeInsets.only(left: leftPad),
      color: theme.colorScheme.surfaceContainerLowest,
      child: Row(children: [
        IconButton(
          icon: Icon(embedded ? Icons.close : Icons.arrow_back, size: 16),
          onPressed: () =>
              embedded ? onClose!() : Navigator.of(context).pop(),
          padding: const EdgeInsets.all(4),
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          iconSize: 16,
        ),
        const Spacer(),
        Text(s.about,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface)),
        const Spacer(),
        // Balance the leading close button + padding so the title stays centred.
        SizedBox(width: leftPad + 36),
      ]),
    );
  }
}
