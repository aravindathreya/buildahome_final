import 'package:buildAhome/chat_v1/chat_v1_doc_client_notice.dart';
import 'package:buildAhome/chat_v1/chat_v1_doc_clarification.dart';
import 'package:buildAhome/chat_v1/chat_v1_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const team = [
    DocClarificationPerson(
      userId: '4',
      name: 'Meera Nair',
      role: 'Site Engineer',
    ),
    DocClarificationPerson(
      userId: '9',
      name: 'Client One',
      role: 'Client',
    ),
    DocClarificationPerson(
      userId: '12',
      name: 'Anita Shah',
      role: 'Project Coordinator',
    ),
    DocClarificationPerson(
      userId: '21',
      name: 'Asha Rao',
      role: 'Home Owner',
    ),
  ];

  test('creating a DOC tags only the project clients', () {
    final notice = buildDocCreatedClientNotice(
      people: team,
      description: 'Extra tiling',
    );

    expect(notice.userIds, [21, 9]);
    expect(notice.body.startsWith('@Asha @Client '), isTrue);
    expect(
      notice.body,
      contains('A Difference of Cost was created (“Extra tiling”).'),
    );
    expect(notice.body.contains('@Meera'), isFalse);
    expect(notice.body.contains('@Anita'), isFalse);
  });

  test('pending DOCs become client tasks that open that chat', () {
    final now = DateTime.utc(2026, 10, 6);
    final tasks = clientDocCreatedTasks(
      docs: [
        ChatV1DocRequest(
          id: 'doc-1',
          description: 'Extra tiling',
          amount: 1200,
          createdBy: 'PC',
          createdAt: now,
          updatedAt: now,
        ),
        ChatV1DocRequest(
          id: 'doc-2',
          description: 'Already approved',
          amount: 50,
          createdBy: 'PC',
          createdAt: now,
          updatedAt: now,
          status: ChatV1DocStatus.approved,
        ),
      ],
      seenIds: const {},
    );

    expect(tasks, hasLength(1));
    expect(tasks.single.title, 'DOC is created: Extra tiling');
    expect(tasks.single.contextType, kChatV1DocCreatedContext);
    expect(tasks.single.contextId, 'doc-1');
    expect(tasks.single.unread, 1);
    expect(tasks.single.kindLabel, 'Difference of Cost');
  });

  test('opening a DOC chat clears only that green count', () {
    final now = DateTime.utc(2026, 10, 6);
    ChatV1DocRequest doc(String id) {
      return ChatV1DocRequest(
        id: id,
        description: id,
        amount: 10,
        createdBy: 'PC',
        createdAt: now,
        updatedAt: now,
      );
    }

    final tasks = clientDocCreatedTasks(
      docs: [doc('a'), doc('b')],
      seenIds: const {'a'},
    );

    expect(tasks.map((task) => task.unread), [0, 1]);
    expect(
      clientDocUnseenCount(docs: [doc('a'), doc('b')], seenIds: const {'a'}),
      1,
    );
  });
}
