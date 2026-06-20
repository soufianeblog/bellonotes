// Web-safe unit test for the platform bridge's shared helpers. Contains no
// `dart:io` so it can also run in a real browser via
// `flutter test --platform chrome`, exercising the web compilation path.
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:bellonotes/platform/picked_file.dart';

void main() {
  test('mimeFromFileName maps common image extensions', () {
    expect(mimeFromFileName('photo.png'), 'image/png');
    expect(mimeFromFileName('PHOTO.PNG'), 'image/png');
    expect(mimeFromFileName('a.jpg'), 'image/jpeg');
    expect(mimeFromFileName('a.jpeg'), 'image/jpeg');
    expect(mimeFromFileName('a.gif'), 'image/gif');
    expect(mimeFromFileName('a.webp'), 'image/webp');
    expect(mimeFromFileName('noext'), 'application/octet-stream');
    expect(mimeFromFileName('weird.xyz'), 'application/octet-stream');
  });

  test('PickedFile carries name and bytes', () {
    final pf = PickedFile('x.zip', Uint8List.fromList([1, 2, 3]));
    expect(pf.name, 'x.zip');
    expect(pf.bytes, [1, 2, 3]);
  });
}
