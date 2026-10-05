import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buildAhome/chat_v1/chat_v1_api.dart';
import 'package:buildAhome/chat_v1/chat_v1_controller.dart';
import 'package:buildAhome/chat_v1/chat_v1_mapper.dart';
import 'package:buildAhome/chat_v1/chat_v1_mention_draft.dart';
import 'package:buildAhome/chat_v1/chat_v1_mentions.dart';
import 'package:buildAhome/chat_v1/chat_v1_utils.dart';
import 'package:buildAhome/chat_v1/widgets/chat_v1_composer.dart';
import 'package:buildAhome/chat_v1/widgets/chat_v1_message_bubble.dart';

class CapturingApi extends ChatV1Api {
  CapturingApi() : super.forTesting();
  Map<String, dynamic>? lastBody;
  String? lastPath;

  @override
  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    lastPath = path;
    lastBody = body;
    return {
      'message': {
        'id': 12,
        'conversation_id': 1,
        'sender_id': 2,
        'sender_name': 'Aravind',
        'body': body!['body'],
        'created_at': '2026-10-04T17:24:00',
        'mentions': [
          for (final id in (body['mentioned_user_ids'] as List? ?? []))
            {'user_id': id, 'name': 'Alex Kumar'},
        ],
      }
    };
  }
}

const alex =
    ChatV1MentionPerson(userId: '7', name: 'Alex Kumar', role: 'Architect');
const otherAlex =
    ChatV1MentionPerson(userId: '9', name: 'Alex Kumar', role: 'Site Engineer');
const priya = ChatV1MentionPerson(userId: '8', name: 'Priya Rao');
const people = [alex, otherAlex, priya];

String pick(
        ChatV1MentionDraft draft, String text, ChatV1MentionPerson person) =>
    draft
        .insert(
            text: text,
            trigger: detectChatMentionTrigger(text, text.length)!,
            person: person,
            people: people)
        .text;

void main() {
  test('identical display names retain the exact selected user ID', () {
    final draft = ChatV1MentionDraft();
    expect(pick(draft, '@', otherAlex), '@AlexKumar ');
    expect(draft.mentionedUserIds, [9]);
  });

  test('body edits and inserted text before a tag retain its identity', () {
    final draft = ChatV1MentionDraft();
    final text = pick(draft, '@', alex);
    draft.updateText(text + 'Please check');
    draft.updateText('Hi ' + text + 'Please check');
    expect(draft.mentionedUserIds, [7]);
  });

  test('editing a tag or extending its token stops tagging that person', () {
    for (final next in ['@AlexKumara hello', '@Alexa hello']) {
      final draft = ChatV1MentionDraft();
      pick(draft, '@', alex);
      draft.updateText(next);
      expect(draft.mentionedUserIds, isEmpty);
    }
  });

  test('deleting one identical token preserves the other selected person', () {
    final draft = ChatV1MentionDraft();
    final first = pick(draft, '@', alex);
    pick(draft, '$first @', otherAlex);
    draft.updateText('  @AlexKumar ');
    expect(draft.mentionedUserIds, [9]);
  });

  test('multiple people are retained and repeated selections are deduplicated',
      () {
    final draft = ChatV1MentionDraft();
    final first = pick(draft, '@', alex);
    final second = pick(draft, '$first @', priya);
    pick(draft, '$second @', alex);
    expect(draft.mentionedUserIds, [7, 8]);
  });

  test('deleting the tag sends explicit empty IDs; clearing resets the draft',
      () {
    final draft = ChatV1MentionDraft();
    expect(draft.mentionedUserIds, isNull);
    pick(draft, '@', alex);
    draft.updateText('Please check');
    expect(draft.mentionedUserIds, isEmpty);
    draft.updateText('');
    draft.updateText('@Priya manual legacy mention');
    expect(draft.mentionedUserIds, isNull);
  });

  test('mobile REST transport includes selected IDs and reply metadata',
      () async {
    final api = CapturingApi();
    final result = await api.sendMessage('1',
        body: '@AlexKumar please check',
        parentMessageId: 4,
        mentionedUserIds: [9]);
    expect(api.lastPath, endsWith('/conversations/1/messages'));
    expect(api.lastBody!['mentioned_user_ids'], [9]);
    expect(api.lastBody!['parent_message_id'], 4);
    expect(result['mentions'], [
      {'user_id': 9, 'name': 'Alex Kumar'}
    ]);
  });

  test('legacy sends omit explicit IDs and removed tags send an empty list',
      () async {
    final api = CapturingApi();
    await api.sendMessage('1', body: '@Alex legacy');
    expect(api.lastBody!.containsKey('mentioned_user_ids'), isFalse);
    await api.sendMessage('1', body: '@AlexKumar edited', mentionedUserIds: []);
    expect(api.lastBody!['mentioned_user_ids'], isEmpty);
  });

  final base = <String, dynamic>{
    'id': 12,
    'sender_id': 2,
    'body': '@Alex please check',
    'created_at': '2026-10-04T17:24:00',
  };
  final tagRows = [
    {'user_id': 7, 'name': 'Alex Kumar'}
  ];

  test('cached plain messages gain confirmed tags without changing body', () {
    final plain = ChatV1Mapper.messageFromJson(base, currentUserId: '7');
    final tagged = ChatV1Mapper.messageFromJson({...base, 'mentions': tagRows},
        currentUserId: '7');
    expect(ChatV1Utils.messageMentionsEqual(plain, tagged), isFalse);
    final merged = ChatV1Controller.preferRicherMessage(plain, tagged);
    expect(merged.mentions.single.userId, '7');
    expect(merged.mentionsResolved, isTrue);
  });

  test('partial events retain tags and explicit empty metadata removes them',
      () {
    final tagged = ChatV1Mapper.messageFromJson({...base, 'mentions': tagRows},
        currentUserId: '7');
    final partial = ChatV1Mapper.messageFromJson(base, currentUserId: '7');
    expect(
        ChatV1Controller.preferRicherMessage(tagged, partial)
            .mentions
            .single
            .userId,
        '7');
    final cleared = ChatV1Mapper.messageFromJson({...base, 'mentions': []},
        currentUserId: '7');
    expect(ChatV1Controller.preferRicherMessage(tagged, cleared).mentions,
        isEmpty);
    final stillPartial = ChatV1Controller.preferRicherMessage(partial, partial);
    expect(stillPartial.mentionsResolved, isFalse);
  });

  testWidgets(
      'picker selection reaches REST and renders green for its recipient',
      (tester) async {
    final text = TextEditingController();
    addTearDown(text.dispose);
    final draft = ChatV1MentionDraft();
    final api = CapturingApi();
    Map<String, dynamic>? saved;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: Align(
        alignment: Alignment.bottomCenter,
        child: ChatComposer(
          controller: text,
          mentionPeople: people,
          mentionDraft: draft,
          onCamera: () {},
          onGallery: () {},
          onDocument: () {},
          onSend: () async {
            saved = await api.sendMessage('1',
                body: text.text, mentionedUserIds: draft.mentionedUserIds);
          },
        ),
      )),
    ));
    await tester.enterText(find.byType(TextField), '@');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Site Engineer'));
    await tester.pumpAndSettle();
    expect(text.text, '@AlexKumar ');
    expect(draft.mentionedUserIds, [9]);
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(api.lastBody!['mentioned_user_ids'], [9]);
    final ctrl = ChatV1Controller.instance;
    final oldId = ctrl.currentUserId;
    addTearDown(() => ctrl.currentUserId = oldId);
    ctrl.currentUserId = '9';
    final message = ChatV1Mapper.messageFromJson(saved!, currentUserId: '9');
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: Cv1MessageBubble(message: message)),
    ));
    expect(find.text('@You'), findsOneWidget);
    expect(find.text('You were tagged here'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
