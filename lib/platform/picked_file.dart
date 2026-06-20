// Shared (platform-agnostic) types for the platform bridge. Kept free of any
// `dart:io` / `dart:html` imports so it can be referenced from either side.
import 'dart:typed_data';

/// A file selected by the user: its display [name] and raw [bytes].
class PickedFile {
  final String name;
  final Uint8List bytes;
  const PickedFile(this.name, this.bytes);
}

/// Best-effort image MIME type from a file name's extension. Used when encoding
/// an attachment as a `data:` URL (web) so the browser renders it correctly.
String mimeFromFileName(String name) {
  final ext = name.toLowerCase().split('.').last;
  switch (ext) {
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'gif':
      return 'image/gif';
    case 'webp':
      return 'image/webp';
    case 'bmp':
      return 'image/bmp';
    case 'svg':
      return 'image/svg+xml';
    default:
      return 'application/octet-stream';
  }
}
