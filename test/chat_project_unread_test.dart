import 'package:buildAhome/chat_v1/chat_v1_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('groups unread chats by sales SOP id and ERP project id', () {
    final hints = ChatProjectUnread.fromConversationRows([
      {
        'id': 41,
        'title': 'General',
        'context_type': 'sales_sop',
        'context_id': 1038,
        'project_id': 3326859,
        'unread_count': 2,
        'last_message_at': '2026-10-05T10:00:00Z',
      },
      {
        'id': 42,
        'title': 'Internal',
        'sales_sop_id': 1038,
        'unread_count': 0,
      },
      {
        'id': 77,
        'title': 'Site',
        'context_type': 'erp_task',
        'context_id': 999,
        'sales_sop_id': 1038,
        'unread_count': 1,
        'last_message_at': '2026-10-05T12:00:00Z',
      },
    ]);

    expect(hints['1038']?.unread, 3);
    expect(hints['3326859']?.unread, 2);
    expect(hints['1038']?.conversationId, '77');
    expect(hints['1038']?.conversationTitle, 'Site');
    expect(hints.containsKey('999'), isFalse);
    expect(hints.containsKey('42'), isFalse);
  });

  test('reads unread from a nested membership when the row count is zero', () {
    expect(
      ChatProjectUnread.rowUnread({
        'unread_count': 0,
        'membership': {'unread_count': 4},
      }),
      4,
    );
  });
}
