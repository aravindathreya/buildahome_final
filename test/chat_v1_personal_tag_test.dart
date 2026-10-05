import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buildAhome/chat_v1/chat_v1_controller.dart';
import 'package:buildAhome/chat_v1/chat_v1_models.dart';
import 'package:buildAhome/chat_v1/chat_v1_mapper.dart';
import 'package:buildAhome/chat_v1/chat_v1_theme.dart';
import 'package:buildAhome/chat_v1/widgets/chat_v1_chat_tile.dart';
import 'package:buildAhome/chat_v1/widgets/chat_v1_mention_banner.dart';
import 'package:buildAhome/chat_v1/widgets/chat_v1_message_bubble.dart';

void main() {
  testWidgets('green personal badge appears only with unread mention metadata',
      (tester) async {
    final item = ChatV1Mapper.conversationToChatItem({
      'id': 1,
      'title': 'General',
      'unread_count': 1,
      'unread_mention_count': 1,
      'unread_mention_message_id': 12,
      'last_message': {'body': '@Test hi'},
    });
    expect(item.unreadMentionMessageId, '12');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Cv1ChatTile(item: item, onTap: () {}))));
    expect(find.text('@'), findsOneWidget);
    expect(find.textContaining('You were tagged'), findsOneWidget);
    final badge = tester.widget<Container>(find
        .ancestor(of: find.text('@'), matching: find.byType(Container))
        .first);
    expect((badge.decoration! as BoxDecoration).color, ChatV1Theme.unread);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Cv1ChatTile(
                item: item.copyWith(mentionsSeen: true), onTap: () {}))));
    expect(find.text('@'), findsNothing);
    expect(find.textContaining('You were tagged'), findsNothing);
  });

  testWidgets('tag banner invokes view-message action', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Cv1MentionBanner(onTap: () => taps++))));
    expect(find.text('You were tagged'), findsOneWidget);
    await tester.tap(find.text('View message'));
    expect(taps, 1);
  });

  for (final dark in [false, true]) {
    testWidgets('personal message label only for tagged recipient dark=$dark',
        (tester) async {
      final ctrl = ChatV1Controller.instance;
      final oldId = ctrl.currentUserId;
      addTearDown(() => ctrl.currentUserId = oldId);
      ctrl.currentUserId = '7';
      final msg = ChatV1Message(
        id: '12',
        authorId: '2',
        authorName: 'Aravind',
        authorInitials: 'A',
        authorColor: Colors.green,
        body: '@Test hi',
        sentAt: DateTime(2026, 10, 4),
        type: ChatV1MsgType.text,
        mentions: const [ChatV1Mention(userId: '7', name: 'Test User')],
      );
      Future<void> show(ChatV1Message message) => tester.pumpWidget(MaterialApp(
            theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light),
            home: Scaffold(
                body: Cv1MessageBubble(message: message, showAuthor: false)),
          ));
      await show(msg);
      expect(find.text('You were tagged here'), findsOneWidget);
      expect(find.text('@You'), findsOneWidget);
      final bubble = tester.widget<Container>(find
          .ancestor(
              of: find.byKey(const ValueKey('personal-mention-chip')),
              matching: find.byType(Container))
          .first);
      final decoration = bubble.decoration! as BoxDecoration;
      expect((decoration.border! as Border).left.color, ChatV1Theme.unread);
      final text = tester.widget<Text>(find.byWidgetPredicate(
          (w) => w is Text && w.textSpan?.toPlainText() == '@Test User hi'));
      final tag = (text.textSpan! as TextSpan).children!.first as TextSpan;
      expect(tag.style!.color,
          dark ? const Color(0xFF7DE5A8) : const Color(0xFF157A42));
      ctrl.currentUserId = '8';
      await show(msg);
      expect(find.text('You were tagged here'), findsNothing);
      expect(find.text('@You'), findsNothing);
      ctrl.currentUserId = '7';
      await show(msg.copyWith(isDeleted: true));
      expect(find.text('You were tagged here'), findsNothing);
      expect(find.text('@You'), findsNothing);
    });
  }
}
