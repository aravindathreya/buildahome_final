import 'chat_v1_doc_clarification.dart';
import 'chat_v1_mentions.dart';
import 'chat_v1_models.dart';

/// Message posted in Upgrades & Additions when a Difference of Cost is created.
class DocCreatedClientNotice {
  final String body;
  final List<int> userIds;

  const DocCreatedClientNotice({
    required this.body,
    required this.userIds,
  });

  bool get hasTags => userIds.isNotEmpty;
}

bool isClientMemberRole(String role) {
  final n = role
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
  return n == 'client' || n == 'home owner' || n == 'homeowner';
}

/// Tags every project client so the DOC channel shows a green unread count
/// and an @ mention that this Difference of Cost was created.
DocCreatedClientNotice buildDocCreatedClientNotice({
  required List<DocClarificationPerson> people,
  required String description,
}) {
  final clients = <DocClarificationPerson>[];
  final seen = <String>{};
  for (final person in people) {
    if (!isClientMemberRole(person.role) || person.userId.trim().isEmpty) {
      continue;
    }
    if (!seen.add(person.userId)) continue;
    clients.add(person);
  }
  clients.sort(
    (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
  );

  final mentionPeople = [
    for (final person in clients)
      ChatV1MentionPerson(
        userId: person.userId,
        name: person.name.trim().isEmpty ? 'Client' : person.name.trim(),
        role: person.role,
      ),
  ];
  final tokens = [
    for (final person in mentionPeople) chatMentionToken(person, mentionPeople),
  ];
  final ids = <int>[];
  for (final person in mentionPeople) {
    final id = int.tryParse(person.userId);
    if (id != null && id > 0) ids.add(id);
  }

  final about = description.trim();
  final subject = about.isEmpty
      ? 'A Difference of Cost was created.'
      : 'A Difference of Cost was created (“$about”).';
  final lead = tokens.isEmpty ? '' : '${tokens.join(' ')} ';
  return DocCreatedClientNotice(
    body: '${lead}$subject Please review it in chat.',
    userIds: ids,
  );
}

DocCreatedClientNotice docCreatedNoticeFromMemberRows(
  List<Map<String, dynamic>> rows, {
  required String description,
}) {
  return buildDocCreatedClientNotice(
    people: docClarificationPeopleFromRows(rows),
    description: description,
  );
}

/// Pending DOCs become client tasks. [seenIds] are docs whose chat was opened.
List<ChatV1TaskItem> clientDocCreatedTasks({
  required List<ChatV1DocRequest> docs,
  required Set<String> seenIds,
}) {
  final tasks = <ChatV1TaskItem>[];
  for (final doc in docs) {
    if (doc.status != ChatV1DocStatus.pending || doc.id.trim().isEmpty) {
      continue;
    }
    final desc = doc.description.trim();
    final seen = seenIds.contains(doc.id);
    tasks.add(ChatV1TaskItem(
      id: 'doc_created_${doc.id}',
      title: desc.isEmpty ? 'DOC is created' : 'DOC is created: $desc',
      category: 'Difference of Cost',
      status: ChatV1TaskStatus.pending,
      assignee: '',
      assigneeInitials: 'DOC',
      lastActivity: doc.updatedAt,
      unread: seen ? 0 : 1,
      lastMessagePreview: 'Open this chat to review the Difference of Cost',
      hasMessages: true,
      contextType: kChatV1DocCreatedContext,
      contextId: doc.id,
    ));
  }
  return tasks;
}

int clientDocUnseenCount({
  required List<ChatV1DocRequest> docs,
  required Set<String> seenIds,
}) {
  var count = 0;
  for (final doc in docs) {
    if (doc.status != ChatV1DocStatus.pending || doc.id.trim().isEmpty) {
      continue;
    }
    if (!seenIds.contains(doc.id)) count++;
  }
  return count;
}
