import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:bellonotes/services/quill_html.dart';

void main() {
  group('deltaToHtml', () {
    test('renders headings and paragraphs', () {
      final d = Delta()
        ..insert('My Title')
        ..insert('\n', {'header': 1})
        ..insert('Some body text')
        ..insert('\n');
      final html = QuillHtml.deltaToHtml(d);
      expect(html, contains('<h1>My Title</h1>'));
      expect(html, contains('<p>Some body text</p>'));
    });

    test('renders inline bold/italic', () {
      final d = Delta()
        ..insert('bold', {'bold': true})
        ..insert(' and ')
        ..insert('italic', {'italic': true})
        ..insert('\n');
      final html = QuillHtml.deltaToHtml(d);
      expect(html, contains('<strong>bold</strong>'));
      expect(html, contains('<em>italic</em>'));
    });

    test('renders unordered lists', () {
      final d = Delta()
        ..insert('one')
        ..insert('\n', {'list': 'bullet'})
        ..insert('two')
        ..insert('\n', {'list': 'bullet'});
      final html = QuillHtml.deltaToHtml(d);
      expect(html, contains('<ul>'));
      expect(html, contains('<li>one</li>'));
      expect(html, contains('<li>two</li>'));
    });

    test('escapes HTML special characters', () {
      final d = Delta()
        ..insert('a < b & c')
        ..insert('\n');
      final html = QuillHtml.deltaToHtml(d);
      expect(html, contains('a &lt; b &amp; c'));
    });

    test('renders text color, highlight and size as span styles', () {
      final d = Delta()
        ..insert('red', {'color': '#d93025'})
        ..insert('hi', {'background': '#fdd663'})
        ..insert('big', {'size': '24'})
        ..insert('\n');
      final html = QuillHtml.deltaToHtml(d);
      expect(html, contains('color:#d93025'));
      expect(html, contains('background-color:#fdd663'));
      expect(html, contains('font-size:24px'));
    });

    test('renders paragraph alignment', () {
      final d = Delta()
        ..insert('centered')
        ..insert('\n', {'align': 'center'});
      final html = QuillHtml.deltaToHtml(d);
      expect(html, contains('text-align:center'));
    });

    test('renders a table block embed to an HTML table', () {
      final d = Delta()
        ..insert('before\n')
        ..insert({
          'table':
              '{"rows":[["H1","H2"],["a","b"]]}'
        })
        ..insert('\n');
      final html = QuillHtml.deltaToHtml(d);
      expect(html, contains('<table>'));
      expect(html, contains('<th>H1</th>'));
      expect(html, contains('<td>a</td>'));
    });

    test('converts a pipe table to a real HTML table', () {
      final d = Delta()
        ..insert('| A | B |')
        ..insert('\n')
        ..insert('| --- | --- |')
        ..insert('\n')
        ..insert('| 1 | 2 |')
        ..insert('\n');
      final html = QuillHtml.deltaToHtml(d);
      expect(html, contains('<table>'));
      expect(html, contains('<th>A</th>'));
      expect(html, contains('<td>1</td>'));
      expect(html, isNot(contains('| A | B |')));
    });
  });

  group('round-trip html ⇄ delta', () {
    test('headings + bold survive a round trip', () {
      final original = Delta()
        ..insert('Heading')
        ..insert('\n', {'header': 2})
        ..insert('hello ')
        ..insert('world', {'bold': true})
        ..insert('\n');
      final html = QuillHtml.deltaToHtml(original);
      final back = QuillHtml.htmlToDelta(html);
      final plain = back
          .toList()
          .map((op) => op.data is String ? op.data as String : '')
          .join();
      expect(plain, contains('Heading'));
      expect(plain, contains('hello world'));
      // The bold attribute must be preserved on the right run.
      final boldOp = back
          .toList()
          .firstWhere((op) => (op.attributes?['bold'] == true), orElse: () => back.toList().first);
      expect(boldOp.attributes?['bold'], true);
    });
  });
}
