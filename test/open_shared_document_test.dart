import 'package:flutter_test/flutter_test.dart';

import 'package:buildAhome/widgets/open_shared_document.dart';

void main() {
  test('pdf and office files open in the app', () {
    final pdf = planSharedDocumentOpen(
      url: 'https://office.buildahome.in/files/quote.pdf',
      fileName: 'quote.pdf',
    );
    expect(pdf.inApp, isTrue);
    expect(pdf.contentType, 'application/pdf');

    final costing = planSharedDocumentOpen(
      url: 'https://office.buildahome.in/serve_sales_sop_costing_sheet/3',
      fileName: 'Costing sheet',
    );
    expect(costing.inApp, isTrue);
    expect(costing.contentType, 'application/pdf');

    final photo = planSharedDocumentOpen(
      url: '/uploads/site.jpg',
      fileName: 'site.jpg',
      contentType: 'image/jpeg',
    );
    expect(photo.inApp, isTrue);
    expect(photo.url, 'https://office.buildahome.in/uploads/site.jpg');
    expect(photo.contentType, 'image/jpeg');
  });

  test('plain links stay as links', () {
    final link = planSharedDocumentOpen(
      url: 'https://maps.google.com/place/site',
      fileName: 'Site map',
    );
    expect(link.inApp, isFalse);
    expect(link.url, 'https://maps.google.com/place/site');
  });

  test('splits message links and keeps trailing punctuation', () {
    final pieces = splitPlainTextLinks(
      'See https://office.buildahome.in/files/plan.pdf, and https://example.com/info.',
    );
    expect(pieces.where((piece) => piece.isLink).map((piece) => piece.text), [
      'https://office.buildahome.in/files/plan.pdf',
      'https://example.com/info',
    ]);
    expect(
      pieces.map((piece) => piece.text).join(),
      'See https://office.buildahome.in/files/plan.pdf, and https://example.com/info.',
    );
  });
}
