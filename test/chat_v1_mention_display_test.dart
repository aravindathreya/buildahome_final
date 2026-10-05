import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buildAhome/chat_v1/chat_v1_mentions.dart';
import 'package:buildAhome/chat_v1/chat_v1_models.dart';
import 'package:buildAhome/chat_v1/widgets/chat_v1_message_bubble.dart';

void main() {
  const mentions = [
    ChatV1Mention(userId: '2', name: 'Ann Smith'),
    ChatV1Mention(userId: '3', name: 'Bob Ray'),
  ];

  test('shows all confirmed people with full readable names', () {
    final segments = splitChatMentionSegments('Hi @Ann and @Bob!',
        mentions: mentions, currentUserId: '2');
    expect(segments.map((s) => s.text).join(), 'Hi @Ann Smith and @Bob Ray!');
    expect(segments.where((s) => s.isMention).length, 2);
    expect(segments.where((s) => s.isSelf).single.text, '@Ann Smith');
  });

  test('compact, full, repeated and case-insensitive tags keep punctuation',
      () {
    final segments = splitChatMentionSegments(
        '(@annsmith), @Ann Smith!\n@Bob @Ann',
        mentions: mentions);
    expect(segments.map((s) => s.text).join(),
        '(@Ann Smith), @Ann Smith!\n@Bob Ray @Ann Smith');
    expect(segments.where((s) => s.isMention).length, 4);
  });

  test('unknown handles, emails and longer unrelated names stay plain', () {
    const body = 'a@Ann.com @Unknown @Annette @AnnSmithson';
    final segments = splitChatMentionSegments(body, mentions: mentions);
    expect(segments.map((s) => s.text).join(), body);
    expect(segments.any((s) => s.isMention), isFalse);
    expect(splitChatMentionSegments('@Ann').single.isMention, isFalse);
  });

  test('shared first names do not display the wrong person', () {
    final segments =
        splitChatMentionSegments('@AnnSmith @AnnLee @Ann', mentions: const [
      ChatV1Mention(userId: '2', name: 'Ann Smith'),
      ChatV1Mention(userId: '4', name: 'Ann Lee'),
    ]);
    expect(segments.map((s) => s.text).join(), '@Ann Smith @Ann Lee @Ann');
    expect(segments.where((s) => s.isMention).length, 2);
  });

  for (final mine in [false, true]) {
    for (final dark in [false, true]) {
      testWidgets('bubble shows other tagged users: mine=$mine dark=$dark',
          (tester) async {
        final msg = ChatV1Message(
          id: '1',
          authorId: '9',
          authorName: 'Sender',
          authorInitials: 'S',
          authorColor: Colors.green,
          body: 'Hi @Ann and @Bob',
          sentAt: DateTime(2026, 10, 4),
          type: ChatV1MsgType.text,
          isMine: mine,
          mentions: mentions,
        );
        await tester.pumpWidget(MaterialApp(
          theme:
              ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home:
              Scaffold(body: Cv1MessageBubble(message: msg, showAuthor: false)),
        ));
        final rich = tester.widget<Text>(find.byWidgetPredicate((widget) =>
            widget is Text &&
            widget.textSpan?.toPlainText() == 'Hi @Ann Smith and @Bob Ray'));
        final spans = (rich.textSpan! as TextSpan).children!.cast<TextSpan>();
        final tagged = spans.where((s) => s.text!.startsWith('@')).toList();
        expect(tagged.length, 2);
        for (final span in tagged) {
          expect(span.style!.color,
              dark ? const Color(0xFF8AC8FF) : const Color(0xFF0B5CAB));
          expect(span.style!.fontWeight, FontWeight.w600);
          expect(span.style!.backgroundColor, isNull);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
