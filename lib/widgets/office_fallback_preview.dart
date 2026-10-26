import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';

/// Simple in-app preview for Office files when the server PDF conversion
/// is not available: .docx paragraphs as text, the first .xlsx sheet as a
/// table and .rtf as plain text. Returns null when nothing could be read.
Widget? buildOfficeFallbackPreview(Uint8List bytes, String extension) {
  try {
    final ext = extension.toLowerCase();
    if (ext == '.docx' || ext == '.docm') {
      final paragraphs = extractDocxParagraphs(bytes);
      if (paragraphs != null && paragraphs.any((p) => p.trim().isNotEmpty)) {
        return _OfficeTextPreview(text: paragraphs.join('\n'));
      }
    } else if (ext == '.xlsx' || ext == '.xlsm') {
      final rows = extractXlsxRows(bytes);
      if (rows != null && rows.isNotEmpty) {
        return _OfficeTablePreview(rows: rows);
      }
    } else if (ext == '.rtf') {
      final text = extractRtfText(bytes);
      if (text != null && text.trim().isNotEmpty) {
        return _OfficeTextPreview(text: text);
      }
    }
  } catch (e) {
    debugPrint('[OfficeFallbackPreview] $e');
  }
  return null;
}

String? _zipText(Archive archive, String name) {
  final file = archive.findFile(name);
  if (file == null) return null;
  final content = file.content;
  return utf8.decode(content, allowMalformed: true);
}

String _unescapeXml(String value) {
  return value.replaceAllMapped(
    RegExp(r'&(#x[0-9a-fA-F]+|#[0-9]+|amp|lt|gt|quot|apos);'),
    (m) {
      final code = m.group(1)!;
      switch (code) {
        case 'amp':
          return '&';
        case 'lt':
          return '<';
        case 'gt':
          return '>';
        case 'quot':
          return '"';
        case 'apos':
          return "'";
      }
      try {
        final n = code.startsWith('#x')
            ? int.parse(code.substring(2), radix: 16)
            : int.parse(code.substring(1));
        return String.fromCharCode(n);
      } catch (_) {
        return m.group(0)!;
      }
    },
  );
}

/// Paragraph text from word/document.xml (max 5000 paragraphs).
List<String>? extractDocxParagraphs(Uint8List bytes) {
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    final xml = _zipText(archive, 'word/document.xml');
    if (xml == null) return null;
    final out = <String>[];
    final paragraph = RegExp(r'<w:p[\s>][\s\S]*?</w:p>');
    final token = RegExp(r'<w:t(?:\s[^>]*)?>([\s\S]*?)</w:t>|<w:tab/>|<w:br/>|<w:cr/>');
    for (final p in paragraph.allMatches(xml)) {
      final buf = StringBuffer();
      for (final t in token.allMatches(p.group(0)!)) {
        final raw = t.group(0)!;
        if (raw.startsWith('<w:tab')) {
          buf.write('\t');
        } else if (raw.startsWith('<w:br') || raw.startsWith('<w:cr')) {
          buf.write('\n');
        } else {
          buf.write(_unescapeXml(t.group(1) ?? ''));
        }
      }
      out.add(buf.toString());
      if (out.length >= 5000) break;
    }
    return out;
  } catch (e) {
    debugPrint('[OfficeFallbackPreview] docx: $e');
    return null;
  }
}

int _columnIndex(String ref) {
  var n = 0;
  for (final c in ref.toUpperCase().codeUnits) {
    if (c < 65 || c > 90) break;
    n = n * 26 + (c - 64);
  }
  return n - 1;
}

/// Cells of the first worksheet (max [maxRows] x [maxCols]).
List<List<String>>? extractXlsxRows(
  Uint8List bytes, {
  int maxRows = 500,
  int maxCols = 40,
}) {
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    final shared = <String>[];
    final sst = _zipText(archive, 'xl/sharedStrings.xml');
    if (sst != null) {
      final textRe = RegExp(r'<t(?:\s[^>]*)?>([\s\S]*?)</t>');
      for (final si in RegExp(r'<si>([\s\S]*?)</si>').allMatches(sst)) {
        shared.add(textRe
            .allMatches(si.group(1)!)
            .map((m) => _unescapeXml(m.group(1) ?? ''))
            .join());
      }
    }
    var sheet = _zipText(archive, 'xl/worksheets/sheet1.xml');
    if (sheet == null) {
      final names = archive.files
          .map((f) => f.name)
          .where((n) => n.startsWith('xl/worksheets/') && n.endsWith('.xml'))
          .toList()
        ..sort();
      if (names.isEmpty) return null;
      sheet = _zipText(archive, names.first);
    }
    if (sheet == null) return null;

    final rows = <List<String>>[];
    var width = 0;
    final rowRe = RegExp(r'<row\b([^>]*)>([\s\S]*?)</row>');
    final cellRe = RegExp(r'<c\b([^>]*?)(?:/>|>([\s\S]*?)</c>)');
    final valueRe = RegExp(r'<v>([\s\S]*?)</v>');
    final inlineRe = RegExp(r'<t(?:\s[^>]*)?>([\s\S]*?)</t>');
    for (final row in rowRe.allMatches(sheet)) {
      if (rows.length >= maxRows) break;
      final cells = <String>[];
      var next = 0;
      for (final cell in cellRe.allMatches(row.group(2)!)) {
        final attrs = cell.group(1) ?? '';
        final body = cell.group(2) ?? '';
        final ref = RegExp(r'\br="([A-Z]+)').firstMatch(attrs)?.group(1);
        final col = ref != null ? _columnIndex(ref) : next;
        next = col + 1;
        if (col < 0 || col >= maxCols) continue;
        final type = RegExp(r'\bt="([^"]*)"').firstMatch(attrs)?.group(1) ?? '';
        var value = '';
        if (type == 'inlineStr') {
          value = inlineRe
              .allMatches(body)
              .map((m) => _unescapeXml(m.group(1) ?? ''))
              .join();
        } else {
          final v = _unescapeXml(valueRe.firstMatch(body)?.group(1) ?? '');
          if (type == 's') {
            final i = int.tryParse(v.trim());
            value = i != null && i >= 0 && i < shared.length ? shared[i] : '';
          } else if (type == 'b') {
            value = v.trim() == '1' ? 'TRUE' : 'FALSE';
          } else {
            value = v;
          }
        }
        while (cells.length <= col) {
          cells.add('');
        }
        cells[col] = value;
      }
      if (cells.length > width) width = cells.length;
      rows.add(cells);
    }
    while (rows.isNotEmpty && rows.last.every((c) => c.trim().isEmpty)) {
      rows.removeLast();
    }
    if (rows.isEmpty || width == 0) return null;
    for (final r in rows) {
      while (r.length < width) {
        r.add('');
      }
    }
    return rows;
  } catch (e) {
    debugPrint('[OfficeFallbackPreview] xlsx: $e');
    return null;
  }
}

/// Rough plain text from an RTF file.
String? extractRtfText(Uint8List bytes) {
  try {
    var s = latin1.decode(bytes, allowInvalid: true);
    if (!s.trimLeft().startsWith('{\\rtf')) return null;
    s = s.replaceAll(RegExp(r'\{\\\*[^{}]*\}'), '');
    s = s.replaceAll(RegExp(r'\\(par|line)\b ?'), '\n');
    s = s.replaceAll(RegExp(r'\\tab\b ?'), '\t');
    s = s.replaceAllMapped(RegExp(r"\\'([0-9a-fA-F]{2})"),
        (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));
    s = s.replaceAll(RegExp(r'\\[a-zA-Z]+-?\d* ?'), '');
    s = s.replaceAll(RegExp(r'[{}]'), '');
    s = s.replaceAll(RegExp(r'\\([\\{}])'), r'$1');
    return s.trim();
  } catch (_) {
    return null;
  }
}

class _OfficeTextPreview extends StatelessWidget {
  const _OfficeTextPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
        child: SelectableText(
          text,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 14,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}

class _OfficeTablePreview extends StatelessWidget {
  const _OfficeTablePreview({required this.rows});

  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final cols = rows.first.length;
    const border = BorderSide(color: Color(0xFFDDDDDD));
    return ColoredBox(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 80),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const FixedColumnWidth(120),
            columnWidths: const {0: FixedColumnWidth(44)},
            border: const TableBorder(
              horizontalInside: border,
              verticalInside: border,
              bottom: border,
              right: border,
            ),
            children: [
              for (var r = 0; r < rows.length; r++)
                TableRow(
                  decoration: BoxDecoration(
                    color: r == 0 ? const Color(0xFFF2F4F7) : null,
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Text(
                        '${r + 1}',
                        style: const TextStyle(
                            color: Colors.black45, fontSize: 11),
                      ),
                    ),
                    for (var c = 0; c < cols; c++)
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: SelectableText(
                          rows[r][c],
                          maxLines: 4,
                          style: TextStyle(
                            color: Colors.black87,
                            fontSize: 12,
                            fontWeight:
                                r == 0 ? FontWeight.w700 : FontWeight.w400,
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
