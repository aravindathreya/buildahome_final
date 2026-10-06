import 'package:buildAhome/chat_v1/chat_v1_doc_clarification.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const team = [
    DocClarificationPerson(
      userId: '4',
      name: 'Meera Nair',
      role: 'Site Engineer',
    ),
    DocClarificationPerson(
      userId: '12',
      name: 'Anita Shah',
      role: 'Project Coordinator',
    ),
    DocClarificationPerson(
      userId: '18',
      name: 'Ravi Menon',
      role: 'Assistant Project Coordinator',
    ),
    DocClarificationPerson(
      userId: '9',
      name: 'Client One',
      role: 'Client',
    ),
  ];

  test('clarification tags only the project PC and APC', () {
    final draft = buildDocClarificationDraft(
      people: team,
      description: 'Extra tiling',
    );

    expect(draft.userIds, [12, 18]);
    expect(draft.body.startsWith('@Anita @Ravi '), isTrue);
    expect(
      draft.body,
      contains('I need clarification regarding this Difference of Cost (“Extra tiling”)'),
    );
    expect(draft.body.contains('@Meera'), isFalse);
    expect(draft.body.contains('Client'), isFalse);
  });

  test('assistant coordinator is not treated as the project coordinator', () {
    final draft = buildDocClarificationDraft(
      people: const [
        DocClarificationPerson(
          userId: '3',
          name: 'APC Only',
          role: 'APCC',
        ),
      ],
      description: '',
    );

    expect(draft.userIds, [3]);
    expect(draft.body, contains('@APC'));
    expect(draft.body, contains('this Difference of Cost.'));
  });

  test('member rows read nested role and skip people who are not PC or APC', () {
    final people = docClarificationPeopleFromRows(const [
      {
        'user_id': 7,
        'name': 'Priya Rao',
        'job_title': 'Project Co-ordinator',
      },
      {
        'id': 8,
        'user': {
          'name': 'Arun Das',
          'role': 'Assistant project coordinator',
        },
      },
      {
        'user_id': 2,
        'name': 'Architect',
        'role': 'Sr. Arch',
      },
    ]);

    final draft = buildDocClarificationDraft(
      people: people,
      description: 'Window change',
    );

    expect(draft.userIds, [7, 8]);
    expect(draft.body, contains('@Priya'));
    expect(draft.body, contains('@Arun'));
  });
}
