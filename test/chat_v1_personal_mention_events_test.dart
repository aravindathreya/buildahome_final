import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buildAhome/chat_v1/chat_v1_models.dart';
import 'package:buildAhome/chat_v1/chat_v1_personal_mention_events.dart';

Map<String, dynamic> _event({
  dynamic recipient = 7,
  dynamic conversation = 1,
  dynamic message = 12,
}) =>
    {
      'mention': {
        'mentioned_user_id': recipient,
        'conversation_id': conversation,
        'message_id': message,
      },
    };

ChatV1Message _message({
  String id = '12',
  String? conversationId = '1',
  bool mine = false,
  bool deleted = false,
  List<ChatV1Mention> mentions = const [],
  bool mentionsResolved = false,
}) =>
    ChatV1Message(
      id: id,
      conversationId: conversationId,
      authorId: mine ? '7' : '2',
      authorName: 'Aravind',
      authorInitials: 'A',
      authorColor: Colors.purple,
      body: '@Priya Check the site photo.',
      sentAt: DateTime.utc(2026, 10, 5, 6, 30),
      type: ChatV1MsgType.image,
      isMine: mine,
      isDeleted: deleted,
      delivered: false,
      read: true,
      edited: true,
      isPinned: true,
      replyPreview: 'Earlier site photo',
      parentMessageId: '11',
      fileName: 'site.jpg',
      fileMeta: '1.2 KB',
      senderRole: 'Engineer',
      attachments: const [
        ChatV1Attachment(
          id: 'photo-1',
          messageId: '12',
          fileName: 'site.jpg',
          contentType: 'image/jpeg',
          storagePath: 'remote/site.jpg',
          previewBytes: [1, 2, 3],
          fileSize: 1200,
        ),
      ],
      reactions: const [
        ChatV1Reaction(emoji: 'thumbs up', count: 2, mine: true)
      ],
      readSummary: const ChatV1ReadSummary(readCount: 3),
      card: const {'status': 'accepted'},
      mentions: mentions,
      mentionsResolved: mentionsResolved,
    );

void main() {
  test('event before message adds confirmed personal tag when message arrives',
      () {
    final events = ChatV1PersonalMentionEvents();
    expect(
        events.record(_event(), conversationId: '1', currentUserId: '7'), '12');
    expect(events.pendingCount, 1);
    final message = events.apply(_message(),
        currentUserId: '7', currentUserName: 'Priya Rao');
    expect(message.mentions.single.userId, '7');
    expect(message.mentions.single.name, 'Priya Rao');
    expect(message.mentionsResolved, isTrue);
    expect(events.pendingCount, 0);
  });

  test('event after visible message enriches that message without a reload',
      () {
    final events = ChatV1PersonalMentionEvents();
    final visible = _message();
    expect(events.apply(visible, currentUserId: '7'), same(visible));
    events.record(_event(), conversationId: '1', currentUserId: '7');
    final updated = events.apply(visible, currentUserId: '7');
    expect(updated.mentions.single.userId, '7');
    expect(updated.mentions.single.name, isNull);
    expect(events.apply(updated, currentUserId: '7'), same(updated));
  });

  test('unrelated message arrival does not consume the pending personal event',
      () {
    final events = ChatV1PersonalMentionEvents();
    events.record(_event(), conversationId: '1', currentUserId: '7');
    final other = _message(id: '13');
    expect(events.apply(other, currentUserId: '7'), same(other));
    expect(events.pendingCount, 1);
    expect(events.apply(_message(), currentUserId: '7').mentions.single.userId,
        '7');
  });

  test('other recipients and conversations cannot create personal tags', () {
    final events = ChatV1PersonalMentionEvents();
    for (final event in [
      _event(recipient: 8),
      _event(conversation: 2),
      _event(recipient: ''),
      _event(conversation: ''),
      _event(message: ''),
      _event(message: null),
      _event(recipient: null),
      _event(conversation: null),
      _event(message: {'id': 12}),
      _event(recipient: true),
    ]) {
      expect(events.record(event, conversationId: '1', currentUserId: '7'),
          isNull);
    }
    expect(events.pendingCount, 0);
    final message = _message();
    expect(events.apply(message, currentUserId: '7'), same(message));
  });

  test('missing event envelope and empty active identity are rejected', () {
    final events = ChatV1PersonalMentionEvents();
    for (final event in <Map<String, dynamic>?>[
      null,
      {},
      {'mention': '12'},
      {'mention': []},
      {'message_id': 12, 'mentioned_user_id': 7, 'conversation_id': 1},
    ]) {
      expect(events.record(event, conversationId: '1', currentUserId: '7'),
          isNull);
    }
    expect(events.record(_event(), conversationId: '', currentUserId: '7'),
        isNull);
    expect(events.record(_event(), conversationId: '1', currentUserId: ''),
        isNull);
    expect(events.pendingCount, 0);
  });

  test('pending event cannot be applied to another signed-in account', () {
    final events = ChatV1PersonalMentionEvents();
    events.record(_event(), conversationId: '1', currentUserId: '7');
    final message = _message();
    expect(events.apply(message, currentUserId: '8'), same(message));
    expect(events.apply(message, currentUserId: ''), same(message));
    expect(message.mentions, isEmpty);
    expect(
        events.apply(message, currentUserId: '7').mentions.single.userId, '7');
  });

  test('message conversation must match when supplied', () {
    final events = ChatV1PersonalMentionEvents();
    events.record(_event(), conversationId: '1', currentUserId: '7');
    final foreign = _message(conversationId: '2');
    expect(events.apply(foreign, currentUserId: '7'), same(foreign));
    expect(events.pendingCount, 1);
    expect(
        events
            .apply(_message(conversationId: null), currentUserId: '7')
            .mentions
            .single
            .userId,
        '7');
  });

  for (final own in [false, true]) {
    test('own=$own deleted=${!own} messages never gain personal tag', () {
      final events = ChatV1PersonalMentionEvents();
      events.record(_event(), conversationId: '1', currentUserId: '7');
      final message = _message(mine: own, deleted: !own);
      expect(events.apply(message, currentUserId: '7'), same(message));
      expect(message.mentions, isEmpty);
      expect(events.pendingCount, 0);
    });
  }

  test('duplicates consume once and preserve an existing personal mention', () {
    final events = ChatV1PersonalMentionEvents();
    events.record(_event(), conversationId: '1', currentUserId: '7');
    events.record(_event(), conversationId: '1', currentUserId: '7');
    expect(events.pendingCount, 1);
    final tagged = _message(
        mentions: const [ChatV1Mention(userId: '7', name: 'Server name')],
        mentionsResolved: true);
    expect(
        events.apply(tagged, currentUserId: '7', currentUserName: 'Local name'),
        same(tagged));
    expect(tagged.mentions.length, 1);
    expect(tagged.mentions.single.name, 'Server name');
    expect(events.pendingCount, 0);
  });

  test('authoritative empty message metadata is unchanged without an event',
      () {
    final events = ChatV1PersonalMentionEvents();
    final message = _message(mentionsResolved: true);
    expect(events.apply(message, currentUserId: '7'), same(message));
    expect(message.mentions, isEmpty);
    events.record(_event(), conversationId: '1', currentUserId: '7');
    expect(
        events.apply(message, currentUserId: '7').mentions.single.userId, '7');
  });

  test('enrichment preserves other people and all unrelated message fields',
      () {
    final events = ChatV1PersonalMentionEvents();
    events.record(_event(), conversationId: '1', currentUserId: '7');
    final original = _message(
        mentions: const [ChatV1Mention(userId: '8', name: 'Rohit Shah')]);
    final result = events.apply(original,
        currentUserId: '7', currentUserName: ' Priya Rao ');
    expect(result.mentions.map((m) => m.userId), ['8', '7']);
    expect(result.mentions.first, same(original.mentions.first));
    expect(result.mentions.last.name, 'Priya Rao');
    expect(result.id, original.id);
    expect(result.conversationId, original.conversationId);
    expect(result.authorId, original.authorId);
    expect(result.authorName, original.authorName);
    expect(result.authorInitials, original.authorInitials);
    expect(result.authorColor, original.authorColor);
    expect(result.body, original.body);
    expect(result.sentAt, original.sentAt);
    expect(result.type, original.type);
    expect(result.isMine, original.isMine);
    expect(result.isDeleted, original.isDeleted);
    expect(result.delivered, original.delivered);
    expect(result.read, original.read);
    expect(result.edited, original.edited);
    expect(result.isPinned, original.isPinned);
    expect(result.replyPreview, original.replyPreview);
    expect(result.parentMessageId, original.parentMessageId);
    expect(result.fileName, original.fileName);
    expect(result.fileMeta, original.fileMeta);
    expect(result.senderRole, original.senderRole);
    expect(result.attachments, same(original.attachments));
    expect(result.attachments.single.previewBytes, [1, 2, 3]);
    expect(result.reactions, same(original.reactions));
    expect(result.readSummary, same(original.readSummary));
    expect(result.card, same(original.card));
  });

  test('pending memory remains bounded and evicts the oldest message IDs', () {
    final events = ChatV1PersonalMentionEvents();
    for (var id = 1; id <= 1000; id++) {
      events.record(_event(message: id),
          conversationId: '1', currentUserId: '7');
    }
    expect(events.pendingCount, 128);
    final old = _message(id: '1');
    expect(events.apply(old, currentUserId: '7'), same(old));
    expect(
        events.apply(_message(id: '1000'), currentUserId: '7').mentions.length,
        1);
    expect(events.pendingCount, 127);
  });

  test('duplicate IDs do not occupy additional capacity', () {
    final events = ChatV1PersonalMentionEvents(maxPending: 2);
    for (final id in [12, 13, 12, 14]) {
      events.record(_event(message: id),
          conversationId: '1', currentUserId: '7');
    }
    expect(events.pendingCount, 2);
    final evicted = _message();
    expect(events.apply(evicted, currentUserId: '7'), same(evicted));
    expect(events.apply(_message(id: '13'), currentUserId: '7').mentions.length,
        1);
    expect(events.apply(_message(id: '14'), currentUserId: '7').mentions.length,
        1);
    expect(events.pendingCount, 0);
    expect(
        () => ChatV1PersonalMentionEvents(maxPending: 0), throwsArgumentError);
  });
}
