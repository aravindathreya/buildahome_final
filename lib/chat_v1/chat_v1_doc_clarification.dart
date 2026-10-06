import 'chat_v1_mentions.dart';

/// A project member who can be tagged on a Difference of Cost thread.
class DocClarificationPerson {
  final String userId;
  final String name;
  final String role;

  const DocClarificationPerson({
    required this.userId,
    required this.name,
    this.role = '',
  });
}

/// Message posted when a client asks the project's PC and APC to explain a DOC.
class DocClarificationDraft {
  final String body;
  final List<int> userIds;

  const DocClarificationDraft({
    required this.body,
    required this.userIds,
  });

  bool get hasTags => userIds.isNotEmpty;
}

enum _PcApcKind { pc, apc }

class _TaggedPerson {
  final DocClarificationPerson person;
  final _PcApcKind kind;

  const _TaggedPerson(this.person, this.kind);
}

String _normRole(String role) {
  return role
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}

_PcApcKind? pcApcKind(String role) {
  final n = _normRole(role);
  if (n.isEmpty) return null;
  if (n == 'apc' ||
      n == 'apcc' ||
      n.contains('assistant project coordinator') ||
      n.contains('assistant project co ordinator')) {
    return _PcApcKind.apc;
  }
  if (n == 'pc' ||
      n == 'project coordinator' ||
      n == 'project co ordinator') {
    return _PcApcKind.pc;
  }
  return null;
}

String _stringField(Map<String, dynamic> raw, List<String> keys) {
  for (final key in keys) {
    final value = raw[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
  }
  return '';
}

/// Reads sales-SOP member rows, including nested user objects.
List<DocClarificationPerson> docClarificationPeopleFromRows(
  List<Map<String, dynamic>> rows,
) {
  final people = <DocClarificationPerson>[];
  final seen = <String>{};
  for (final row in rows) {
    final user = row['user'];
    final nested = user is Map ? Map<String, dynamic>.from(user) : null;
    final userId = _stringField(row, const ['user_id', 'id']);
    final nestedId = nested == null
        ? ''
        : _stringField(nested, const ['user_id', 'id']);
    final id = userId.isNotEmpty ? userId : nestedId;
    if (id.isEmpty || !seen.add(id)) continue;
    final name = _stringField(
      row,
      const ['name', 'user_name', 'username', 'full_name'],
    );
    final nestedName = nested == null
        ? ''
        : _stringField(nested, const ['name', 'user_name', 'username', 'full_name']);
    final role = _stringField(
      row,
      const ['role', 'job_title', 'designation', 'user_role', 'participant_role'],
    );
    final nestedRole = nested == null
        ? ''
        : _stringField(nested, const [
            'role',
            'job_title',
            'designation',
            'user_role',
          ]);
    people.add(DocClarificationPerson(
      userId: id,
      name: name.isNotEmpty ? name : (nestedName.isNotEmpty ? nestedName : 'User'),
      role: role.isNotEmpty ? role : nestedRole,
    ));
  }
  return people;
}

/// Tags the project's Project Coordinator and Assistant Project Coordinator.
DocClarificationDraft buildDocClarificationDraft({
  required List<DocClarificationPerson> people,
  required String description,
}) {
  final tagged = <_TaggedPerson>[];
  final seen = <String>{};
  for (final person in people) {
    final kind = pcApcKind(person.role);
    if (kind == null || person.userId.trim().isEmpty) continue;
    if (!seen.add(person.userId)) continue;
    tagged.add(_TaggedPerson(person, kind));
  }
  tagged.sort((a, b) {
    final kindOrder = a.kind.index.compareTo(b.kind.index);
    if (kindOrder != 0) return kindOrder;
    return a.person.name.toLowerCase().compareTo(b.person.name.toLowerCase());
  });

  final mentionPeople = [
    for (final tag in tagged)
      ChatV1MentionPerson(
        userId: tag.person.userId,
        name: tag.person.name.trim().isEmpty ? 'User' : tag.person.name.trim(),
        role: tag.person.role,
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
      ? 'this Difference of Cost'
      : 'this Difference of Cost (“$about”)';
  final lead = tokens.isEmpty ? '' : '${tokens.join(' ')} ';
  return DocClarificationDraft(
    body:
        '${lead}I need clarification regarding $subject. Could you please explain the details so I can review it before approving?',
    userIds: ids,
  );
}
