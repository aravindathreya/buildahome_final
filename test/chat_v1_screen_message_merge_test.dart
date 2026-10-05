import 'package:flutter_test/flutter_test.dart';
import 'package:buildAhome/chat_v1/chat_v1_mapper.dart';
import 'package:buildAhome/chat_v1/chat_v1_models.dart';
import 'package:buildAhome/chat_v1/screens/chat_v1_conversation_screen.dart';

const _recipient = {'user_id': 7, 'name': 'Priya Rao'};
final _sentAt = DateTime.parse('2026-10-05T06:30:00Z');

ChatV1Message _message({
  String body = '@Priya Please review the site photo.',
  List<Map<String, dynamic>>? mentions,
  List<ChatV1Attachment> attachments = const [],
}) {
  final message = ChatV1Mapper.messageFromJson({
    'id': 12,
    'conversation_id': 1,
    'sender_id': 2,
    'sender_name': 'Aravind',
    'body': body,
    'created_at': _sentAt.toIso8601String(),
    if (mentions != null) 'mentions': mentions,
  }, currentUserId: '7');
  return attachments.isEmpty
      ? message
      : message.copyWith(attachments: attachments, type: ChatV1MsgType.image);
}

const _localPhoto = ChatV1Attachment(
  id: 'attachment-1',
  messageId: '12',
  fileName: 'site.jpg',
  contentType: 'image/jpeg',
  fileSize: 1200,
  storagePath: 'local/site.jpg',
  previewBytes: [1, 2, 3, 4],
);

void main() {
  test('active screen merger keeps confirmed tags in a partial text event', () {
    final existing = _message(mentions: [_recipient]);
    final incoming = _message();
    expect(incoming.mentionsResolved, isFalse);

    final merged = mergeConversationScreenMessage(existing, incoming);

    expect(merged.mentions.single.userId, '7');
    expect(merged.mentions.single.name, 'Priya Rao');
    expect(merged.mentionsResolved, isTrue);
    expect(merged.body, existing.body);
    expect(merged.sentAt, _sentAt);
    expect(merged.authorId, '2');
    expect(merged.conversationId, '1');
  });

  test('tag metadata refresh updates a cached attachment bubble', () {
    final existing = _message(attachments: [_localPhoto]);
    final incoming = _message(body: '', mentions: [_recipient]);

    final merged = mergeConversationScreenMessage(existing, incoming);

    expect(merged.mentions.single.userId, '7');
    expect(merged.mentionsResolved, isTrue);
    expect(merged.attachments.single.previewBytes, [1, 2, 3, 4]);
    expect(merged.attachments.single.storagePath, 'local/site.jpg');
    expect(merged.attachments.single.fileSize, 1200);
    expect(merged.type, ChatV1MsgType.image);
    expect(merged.body, existing.body);
    expect(merged.sentAt, _sentAt);
  });

  test('attachment upload confirmation adds tags without replacing caption',
      () {
    final existing = _message();
    final incoming = _message(
      body: 'Uploaded: site.jpg',
      mentions: [_recipient],
      attachments: [_localPhoto],
    );

    final merged = mergeConversationScreenMessage(existing, incoming);

    expect(merged.mentions.single.userId, '7');
    expect(merged.attachments.single.fileName, 'site.jpg');
    expect(merged.attachments.single.previewBytes, [1, 2, 3, 4]);
    expect(merged.body, existing.body);
    expect(merged.sentAt, _sentAt);
  });

  test('authoritative empty metadata clears tags while retaining attachments',
      () {
    final existing = _message(
      mentions: [_recipient],
      attachments: [_localPhoto],
    );
    final incoming = _message(body: '', mentions: []);
    expect(incoming.mentionsResolved, isTrue);

    final merged = mergeConversationScreenMessage(existing, incoming);

    expect(merged.mentions, isEmpty);
    expect(merged.mentionsResolved, isTrue);
    expect(merged.attachments.single.previewBytes, [1, 2, 3, 4]);
    expect(merged.attachments.single.id, 'attachment-1');
    expect(merged.body, existing.body);
    expect(merged.sentAt, _sentAt);
  });

  test('remote attachment metadata retains local bytes and confirmed tags', () {
    final existing = _message(
      mentions: [_recipient],
      attachments: [_localPhoto],
    );
    final incoming = _message(
      body: 'Uploaded: site.jpg',
      attachments: [
        const ChatV1Attachment(
          id: '',
          fileName: '',
          contentType: '',
          storagePath: 'remote/site.jpg',
        ),
      ],
    );

    final merged = mergeConversationScreenMessage(existing, incoming);
    final photo = merged.attachments.single;

    expect(merged.mentions.single.userId, '7');
    expect(photo.storagePath, 'remote/site.jpg');
    expect(photo.previewBytes, [1, 2, 3, 4]);
    expect(photo.id, 'attachment-1');
    expect(photo.messageId, '12');
    expect(photo.fileName, 'site.jpg');
    expect(photo.contentType, 'image/jpeg');
    expect(photo.fileSize, 1200);
    expect(merged.body, existing.body);
    expect(merged.sentAt, _sentAt);
  });
}
