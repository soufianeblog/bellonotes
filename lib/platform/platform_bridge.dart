// Platform bridge: a single, web-safe API over the parts of the app that need
// `dart:io` on native and browser APIs on the web — database opening, local
// key/value persistence, file save/pick, image rendering and log file output.
//
// The correct implementation is chosen at compile time: the native (`dart:io`)
// version by default, the web (`package:web`) version when compiling to JS/WASM.
// Shared code only ever imports THIS file, so it never references `dart:io`
// directly and therefore compiles on web.
export 'platform_bridge_io.dart'
    if (dart.library.js_interop) 'platform_bridge_web.dart';
