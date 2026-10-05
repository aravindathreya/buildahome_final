import 'package:flutter_test/flutter_test.dart';

import 'package:buildAhome/chat_v1/chat_v1_mentions.dart';

void main() {
  const ann = ChatV1MentionPerson(
    userId: '2',
    name: 'Ann Smith',
    role: 'Site Engineer',
  );
  const bob = ChatV1MentionPerson(
    userId: '3',
    name: 'Bob Ray',
    role: 'member',
  );
  const ann2 = ChatV1MentionPerson(
    userId: '4',
    name: 'Ann Lee',
    role: 'Architect',
  );

  test('detects @ at start, after space, and filters as the query grows', () {
    expect(detectChatMentionTrigger('', 0), isNull);
    expect(detectChatMentionTrigger('hello', 5), isNull);
    expect(detectChatMentionTrigger('a@bob', 5), isNull);

    final at = detectChatMentionTrigger('@', 1);
    expect(at, isNotNull);
    expect(at!.query, '');
    expect(at.start, 0);

    final mid = detectChatMentionTrigger('hi @an', 6);
    expect(mid!.query, 'an');
    expect(mid.start, 3);

    final people = [ann, bob];
    expect(filterMentionPeople(people, '').map((p) => p.userId), ['2', '3']);
    expect(filterMentionPeople(people, 'ann').single.userId, '2');
    expect(filterMentionPeople(people, 'site').single.userId, '2');
    expect(filterMentionPeople(people, 'member').single.userId, '3');
    expect(bob.displayRole, isEmpty);
    expect(ann.displayRole, 'Site Engineer');
  });

  test('inserts a server-resolvable first-name token and one trailing space',
      () {
    final trigger = detectChatMentionTrigger('ping @an', 8)!;
    final result = applyChatMention(
      text: 'ping @an',
      trigger: trigger,
      person: ann,
      people: [ann, bob],
    );
    expect(result.text, 'ping @Ann ');
    expect(result.caret, result.text.length);

    final kept = applyChatMention(
      text: 'ping @an there',
      trigger: detectChatMentionTrigger('ping @an there', 8)!,
      person: ann,
      people: [ann, bob],
    );
    expect(kept.text, 'ping @Ann there');
    expect(kept.caret, 'ping @Ann '.length);
  });

  test('uses compact name when first names collide', () {
    final people = [ann, ann2];
    expect(chatMentionToken(ann, people), '@AnnSmith');
    expect(chatMentionToken(ann2, people), '@AnnLee');
    expect(chatMentionToken(bob, [ann, bob]), '@Bob');
  });

  test('maps participant rows and skips self and inactive members', () {
    final people = mentionPeopleFromParticipants(
      [
        {
          'user_id': 9,
          'name': 'Me',
          'role': 'Client',
          'is_active': true,
        },
        {
          'user_id': 2,
          'name': 'Ann Smith',
          'role': 'Site Engineer',
          'participant_role': 'member',
          'is_active': true,
        },
        {
          'user_id': 5,
          'name': 'Gone',
          'role': 'QA',
          'is_active': false,
        },
      ],
      excludeUserId: '9',
    );
    expect(people.map((p) => p.userId), ['2']);
    expect(people.single.displayRole, 'Site Engineer');
  });
}
