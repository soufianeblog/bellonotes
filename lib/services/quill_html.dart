import 'dart:convert';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';

/// Converts between Quill [Delta] documents and HTML. The app stores notes as
/// Delta JSON (canonical); HTML is used only for the editor's source toggle and
/// for `.html` export, so the round-trip only needs to cover the formats the
/// editor produces.
class QuillHtml {
  /// HTML → Delta using the well-tested flutter_quill_delta_from_html parser.
  static Delta htmlToDelta(String html) {
    final converter = HtmlToDelta();
    return converter.convert(html);
  }

  /// Delta → HTML. Groups inline runs into lines, then lines into block-level
  /// elements (headings, lists, blockquotes, code blocks, paragraphs, tables).
  static String deltaToHtml(Delta delta) {
    final lines = _splitIntoLines(delta);
    final out = StringBuffer();

    String? openList; // 'ul' | 'ol'
    bool inCode = false;
    final codeBuf = StringBuffer();

    void closeList() {
      if (openList != null) {
        out.writeln('</$openList>');
        openList = null;
      }
    }

    void closeCode() {
      if (inCode) {
        out.write('<pre><code>${codeBuf.toString()}</code></pre>');
        codeBuf.clear();
        inCode = false;
      }
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final attrs = line.attributes;
      final header = attrs['header'];
      final list = attrs['list'];
      final isQuote = attrs['blockquote'] == true;
      final isCode = attrs['code-block'] == true;
      final alignStyle = _alignStyle(attrs['align']);

      if (isCode) {
        closeList();
        inCode = true;
        codeBuf.writeln(_escape(line.plainText));
        continue;
      } else {
        closeCode();
      }

      // Markdown-style pipe table → real <table>.
      if (list == null && _isTableRow(line.plainText)) {
        closeList();
        final table = <_Line>[];
        var j = i;
        while (j < lines.length && _isTableRow(lines[j].plainText)) {
          table.add(lines[j]);
          j++;
        }
        out.writeln(_renderTable(table));
        i = j - 1;
        continue;
      }

      if (list != null) {
        final wantList = (list == 'ordered') ? 'ol' : 'ul';
        if (openList != wantList) {
          closeList();
          out.writeln('<$wantList>');
          openList = wantList;
        }
        final checkAttr = (list == 'checked')
            ? ' data-checked="true"'
            : (list == 'unchecked')
                ? ' data-checked="false"'
                : '';
        out.writeln('<li$checkAttr>${line.html}</li>');
        continue;
      } else {
        closeList();
      }

      if (header == 1) {
        out.writeln('<h1$alignStyle>${line.html}</h1>');
      } else if (header == 2) {
        out.writeln('<h2$alignStyle>${line.html}</h2>');
      } else if (header == 3) {
        out.writeln('<h3$alignStyle>${line.html}</h3>');
      } else if (isQuote) {
        out.writeln('<blockquote$alignStyle>${line.html}</blockquote>');
      } else {
        final content = line.html.isEmpty ? '<br/>' : line.html;
        out.writeln('<p$alignStyle>$content</p>');
      }
    }
    closeList();
    closeCode();
    return out.toString().trim();
  }

  static String _alignStyle(Object? align) {
    if (align is String && align.isNotEmpty) {
      return ' style="text-align:$align"';
    }
    return '';
  }

  static bool _isTableRow(String text) {
    final t = text.trim();
    return t.startsWith('|') && t.endsWith('|') && t.length > 1;
  }

  static List<String> _tableCells(String row) {
    var t = row.trim();
    if (t.startsWith('|')) t = t.substring(1);
    if (t.endsWith('|')) t = t.substring(0, t.length - 1);
    return t.split('|').map((c) => c.trim()).toList();
  }

  static bool _isSeparatorRow(String row) {
    return _tableCells(row)
        .every((c) => c.isNotEmpty && RegExp(r'^:?-+:?$').hasMatch(c));
  }

  static String _renderTable(List<_Line> rows) {
    final sb = StringBuffer('<table>');
    var headerDone = false;
    for (var i = 0; i < rows.length; i++) {
      final cells = _tableCells(rows[i].plainText);
      if (i == 1 && _isSeparatorRow(rows[i].plainText)) continue;
      final isHeader = i == 0 &&
          rows.length > 1 &&
          _isSeparatorRow(rows[1].plainText);
      final tag = isHeader ? 'th' : 'td';
      sb.write('<tr>');
      for (final c in cells) {
        sb.write('<$tag>${_escape(c)}</$tag>');
      }
      sb.write('</tr>');
      if (isHeader) headerDone = true;
    }
    // Avoid unused warning while keeping intent explicit.
    assert(headerDone || rows.isNotEmpty);
    sb.write('</table>');
    return sb.toString();
  }

  // ─── internals ───

  static List<_Line> _splitIntoLines(Delta delta) {
    final lines = <_Line>[];
    var currentHtml = StringBuffer();
    var currentPlain = StringBuffer();

    for (final op in delta.toList()) {
      final data = op.data;
      final attrs = op.attributes ?? const {};
      if (data is String) {
        final parts = data.split('\n');
        for (var i = 0; i < parts.length; i++) {
          if (parts[i].isNotEmpty) {
            currentHtml.write(_inline(parts[i], attrs));
            currentPlain.write(parts[i]);
          }
          if (i < parts.length - 1) {
            lines.add(_Line(currentHtml.toString(), currentPlain.toString(),
                Map<String, dynamic>.from(attrs)));
            currentHtml = StringBuffer();
            currentPlain = StringBuffer();
          }
        }
      } else if (data is Map) {
        final image = data['image'];
        if (image is String) {
          currentHtml.write('<img src="${_escapeAttr(image)}"/>');
        }
        final table = data['table'];
        if (table is String) {
          currentHtml.write(_embedTableToHtml(table));
        }
      }
    }
    if (currentHtml.isNotEmpty || currentPlain.isNotEmpty) {
      lines.add(_Line(currentHtml.toString(), currentPlain.toString(), {}));
    }
    return lines;
  }

  static String _embedTableToHtml(String tableJson) {
    try {
      final decoded = jsonDecode(tableJson);
      final rows = (decoded['rows'] as List)
          .map<List<String>>(
              (r) => (r as List).map((c) => c.toString()).toList())
          .toList();
      final sb = StringBuffer('<table>');
      for (var i = 0; i < rows.length; i++) {
        final tag = i == 0 ? 'th' : 'td';
        sb.write('<tr>');
        for (final c in rows[i]) {
          sb.write('<$tag>${_escape(c)}</$tag>');
        }
        sb.write('</tr>');
      }
      sb.write('</table>');
      return sb.toString();
    } catch (_) {
      return '';
    }
  }

  static String _inline(String text, Map<String, dynamic> attrs) {
    var html = _escape(text);
    if (attrs['code'] == true) html = '<code>$html</code>';
    if (attrs['bold'] == true) html = '<strong>$html</strong>';
    if (attrs['italic'] == true) html = '<em>$html</em>';
    if (attrs['underline'] == true) html = '<u>$html</u>';
    if (attrs['strike'] == true) html = '<s>$html</s>';

    final styles = <String>[];
    final color = attrs['color'];
    if (color is String && color.isNotEmpty) styles.add('color:$color');
    final bg = attrs['background'];
    if (bg is String && bg.isNotEmpty) styles.add('background-color:$bg');
    final size = attrs['size'];
    if (size != null && '$size'.isNotEmpty) {
      final sz = '$size';
      styles.add('font-size:${RegExp(r'^\d+$').hasMatch(sz) ? '${sz}px' : sz}');
    }
    final fontFam = attrs['font'];
    if (fontFam is String && fontFam.isNotEmpty) {
      styles.add('font-family:$fontFam');
    }
    if (styles.isNotEmpty) {
      html = '<span style="${styles.join(';')}">$html</span>';
    }

    final link = attrs['link'];
    if (link is String && link.isNotEmpty) {
      html = '<a href="${_escapeAttr(link)}">$html</a>';
    }
    return html;
  }

  static String _escape(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static String _escapeAttr(String s) =>
      _escape(s).replaceAll('"', '&quot;');
}

class _Line {
  final String html;
  final String plainText;
  final Map<String, dynamic> attributes;
  _Line(this.html, this.plainText, this.attributes);
}
