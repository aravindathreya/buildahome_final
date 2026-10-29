import 'package:buildAhome/services/document_file_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const url1654 = 'https://example.com/files/sales_sop/'
      'framing_drawing_1654_FRAMING_FOR_CLIENT_APPROVAL_27.04.2026.dwg?token=x';

  group('detectDocumentExtension', () {
    test('dwg from URL when name has date dots', () {
      expect(
        detectDocumentExtension(
          name: 'FRAMING FOR CLIENT APPROVAL 27.04.2026',
          url: url1654,
        ),
        'dwg',
      );
    });
    test('name extension wins', () {
      expect(detectDocumentExtension(name: 'a.DXF', url: 'x/y.pdf'), 'dxf');
    });
    test('common types', () {
      for (final e in ['zip', 'rar', 'skp', 'rvt', 'ifc', 'xlsx', 'pdf']) {
        expect(detectDocumentExtension(url: 'https://h/p/file.$e'), e);
      }
    });
    test('unknown or missing -> empty', () {
      expect(detectDocumentExtension(name: 'plan 27.04.2026'), '');
      expect(detectDocumentExtension(url: 'https://h/doc/123'), '');
      expect(detectDocumentExtension(name: null, url: null), '');
      expect(detectDocumentExtension(url: 'https://h.com/a.b/file'), '');
    });
    test('encoded url', () {
      expect(detectDocumentExtension(url: 'https://h/a%20b.dwg#x'), 'dwg');
    });
  });

  test('documentTypeLabel', () {
    expect(documentTypeLabel('dwg'), 'AutoCAD drawing (.dwg)');
    expect(documentTypeLabel('.zip'), 'ZIP archive (.zip)');
    expect(documentTypeLabel('xyz'), 'XYZ file (.xyz)');
    expect(documentTypeLabel(''), 'File');
  });

  test('ensureFileExtension', () {
    expect(ensureFileExtension('Plan 27.04.2026', 'dwg'), 'Plan 27.04.2026.dwg');
    expect(ensureFileExtension('a.DWG', 'dwg'), 'a.DWG');
    expect(ensureFileExtension('a', ''), 'a');
  });
}