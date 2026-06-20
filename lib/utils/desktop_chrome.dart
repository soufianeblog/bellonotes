// Web-safe replacements for the `Platform.isMacOS || ...` checks that decide
// whether to draw the custom desktop window chrome. `dart:io`'s `Platform`
// throws on the web and can't even be imported there, so these use
// `defaultTargetPlatform` (from foundation) gated on `!kIsWeb` instead.
import 'package:flutter/foundation.dart';

/// True only for the desktop platforms that draw the in-app title bar. On the
/// web this is always false (the browser provides the window chrome), even when
/// running on a desktop OS.
bool get isDesktopChrome =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

/// True only for a native macOS window, which must reserve space for the
/// traffic-light buttons overlaid on the top-left of the content view.
bool get isMacOSDesktop =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
