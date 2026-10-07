import 'package:buildAhome/chat_v1/chat_v1_project_summaries.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('project summaries keep unread, last message and the chat to open', () {
    final payload = ChatProjectSummaryPayload.parse({
      'total_unread': 5,
      'projects': [
        {
          'project_id': 15,
          'sales_sop_id': 1038,
          'unread_count': 3,
          'open_conversation_id': 77,
          'open_conversation_title': 'Site',
          'last_message_at': '2026-10-07T18:40:00Z',
          'last_message': {
            'conversation_id': 41,
            'conversation_title': 'General',
            'text': 'Drawings uploaded',
            'type': 'text',
            'sender_name': 'Neha',
            'is_from_me': false,
            'created_at': '2026-10-07T18:40:00Z',
          },
        },
        {
          'project_id': '16',
          'unread_count': 0,
          'last_message': null,
        },
      ],
    })!;

    expect(payload.totalUnread, 5);
    final villa = payload.byKey['15']!;
    expect(payload.byKey['1038'], same(villa));
    expect(villa.unread, 3);
    expect(villa.preview, 'Neha: Drawings uploaded');
    expect(villa.conversation['id'], '77');
    expect(villa.conversation['title'], 'Site');
    expect(villa.activityAt, DateTime.parse('2026-10-07T18:40:00Z'));

    final quiet = payload.byKey['16']!;
    expect(quiet.unread, 0);
    expect(quiet.preview, '');
    expect(quiet.hasActivity, isFalse);
    expect(quiet.conversation, isEmpty);
  });

  test('total falls back to the row sum and odd bodies are rejected', () {
    final payload = ChatProjectSummaryPayload.parse({
      'projects': [
        {'project_id': 1, 'unread_count': 2},
        {'project_id': 2, 'unread_count': '4'},
      ],
    })!;
    expect(payload.totalUnread, 6);

    expect(ChatProjectSummaryPayload.parse({'conversations': []}), isNull);
    expect(ChatProjectSummaryPayload.parse([]), isNull);
  });

  test('last message conversation is opened when no unread target is sent',
      () {
    final summary = ChatProjectSummary.fromJson({
      'project_id': 9,
      'unread_count': 1,
      'last_message': {
        'conversation_id': 41,
        'conversation_title': 'General',
        'text': 'Hi',
        'sender_name': 'Rahul',
      },
    })!;
    expect(summary.conversation['id'], '41');
    expect(summary.conversation['title'], 'General');
  });
}
