import 'package:buildAhome/chat_v1/chat_v1_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('login redirect HTML is not parsed as JSON', () {
    const html = '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 3.2 Final//EN">\n'
        '<title>Redirecting...</title>';

    expect(
      () => decodeDiscussionUpload(302, html),
      throwsA(
        isA<ChatV1ApiException>().having(
          (e) => e.message,
          'message',
          'Please sign in again to upload the file.',
        ),
      ),
    );
  });

  test('upload URL is read from the top level or a nested file', () {
    expect(
      discussionUploadUrl({'url': '/files/diff.pdf'}),
      '/files/diff.pdf',
    );
    expect(
      discussionUploadUrl({
        'file': {'storage_path': '/files/nested.pdf'},
      }),
      '/files/nested.pdf',
    );
  });
}
