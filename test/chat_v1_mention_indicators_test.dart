import 'package:flutter_test/flutter_test.dart';

import 'package:buildAhome/chat_v1/chat_v1_mentions.dart';
import 'package:buildAhome/chat_v1/chat_v1_models.dart';

void main() {
  test('highlights only the current user @name', () {
    const mentions = [
      ChatV1Mention(userId: '7', name: 'Sumukh Ku'),
      ChatV1Mention(userId: '3', name: 'Ann Smith'),
    ];
    final segments = splitSelfMentionSegments(
      'hey @Sumukh and @Ann please look',
      currentUserId: '7',
      currentUserName: 'Sumukh Ku',
      mentions: mentions,
    );
    expect(segments.where((s) => s.isSelf).map((s) => s.text), ['@Sumukh']);
    expect(segments.where((s) => !s.isSelf && s.text.contains('@Ann')).length, 1);
  });

  test('does not highlight someone else mention for this user', () {
    final segments = splitSelfMentionSegments(
      'ping @Ann',
      currentUserId: '7',
      currentUserName: 'Sumukh Ku',
      mentions: const [ChatV1Mention(userId: '3', name: 'Ann Smith')],
    );
    expect(segments.single.isSelf, isFalse);
    expect(segments.single.text, 'ping @Ann');
  });

  test('first name and compact name match the tagged user', () {
    expect(chatTokenMatchesName('Sumukh', 'Sumukh Ku'), isTrue);
    expect(chatTokenMatchesName('SumukhKu', 'Sumukh Ku'), isTrue);
    expect(chatTokenMatchesName('Ann', 'Sumukh Ku'), isFalse);
  });
}