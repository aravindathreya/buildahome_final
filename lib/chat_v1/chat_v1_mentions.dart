import 'chat_v1_models.dart';

/// @mention trigger detection and token insertion.
///
/// Body tokens remain compatible with legacy server mention parsing. Confirmed
/// mention metadata supplies the person's readable name when displaying messages.

final RegExp _trigger = RegExp(r'(^|[\s(])@([^\s@]*)$');
final RegExp _space = RegExp(r'\s+');
final RegExp _leadingSpace = RegExp(r'^\s');
final RegExp _tokenBreak = RegExp(r'[\s@.,!?;:]');

class ChatV1MentionPerson {
  final String userId;
  final String name;
  final String role;
  final String email;
  final bool isActive;

  const ChatV1MentionPerson({
    required this.userId,
    required this.name,
    this.role = '',
    this.email = '',
    this.isActive = true,
  });

  /// Job title when the API sent one. Membership flags like "member" are
  /// omitted so the row stays name-only unless a real role exists.
  String get displayRole {
    final job = role.trim();
    if (job.isEmpty) return '';
    final lower = job.toLowerCase();
    if (lower == 'member' || lower == 'admin' || lower == 'owner') return '';
    return job;
  }

  factory ChatV1MentionPerson.fromParticipant(Map<String, dynamic> raw) {
    final userId = (raw['user_id'] ?? raw['id'] ?? '').toString().trim();
    final name = (raw['name'] ?? raw['user_name'] ?? raw['full_name'] ?? '')
        .toString()
        .trim();
    var role = (raw['role'] ?? '').toString().trim();
    if (role.isEmpty) {
      role = (raw['participant_role'] ?? '').toString().trim();
    }
    final email = (raw['email'] ?? '').toString().trim();
    final activeRaw = raw['is_active'];
    final active =
        activeRaw is bool ? activeRaw : activeRaw?.toString() != 'false';
    return ChatV1MentionPerson(
      userId: userId,
      name: name.isEmpty ? 'User' : name,
      role: role,
      email: email,
      isActive: active,
    );
  }
}

class ChatV1MentionTrigger {
  final int start;
  final int end;
  final String query;

  const ChatV1MentionTrigger({
    required this.start,
    required this.end,
    required this.query,
  });
}

class ChatV1MentionInsertion {
  final String text;
  final int caret;

  const ChatV1MentionInsertion({required this.text, required this.caret});
}

/// Active members of this conversation, excluding the current user.
List<ChatV1MentionPerson> mentionPeopleFromParticipants(
  List<Map<String, dynamic>> rows, {
  String? excludeUserId,
}) {
  final seen = <String>{};
  final people = <ChatV1MentionPerson>[];
  for (final row in rows) {
    final person = ChatV1MentionPerson.fromParticipant(row);
    if (!person.isActive || person.userId.isEmpty) continue;
    if (excludeUserId != null &&
        excludeUserId.isNotEmpty &&
        person.userId == excludeUserId) {
      continue;
    }
    if (!seen.add(person.userId)) continue;
    people.add(person);
  }
  people.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return people;
}

/// Open a picker when the caret sits in an `@query` token, same rule as web
/// `detectMention`: start of text, whitespace, or `(`, then `@` and no space.
ChatV1MentionTrigger? detectChatMentionTrigger(String text, int cursor) {
  if (text.isEmpty) return null;
  var pos = cursor;
  if (pos < 0 || pos > text.length) pos = text.length;
  final before = text.substring(0, pos);
  final match = _trigger.firstMatch(before);
  if (match == null) return null;
  final at = before.lastIndexOf('@');
  if (at < 0) return null;
  return ChatV1MentionTrigger(
    start: at,
    end: pos,
    query: match.group(2) ?? '',
  );
}

bool chatMentionMatches(ChatV1MentionPerson person, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  final name = person.name.toLowerCase();
  final role = person.displayRole.toLowerCase();
  final rawRole = person.role.toLowerCase();
  final first = name.split(_space).first;
  return name.contains(q) ||
      first.contains(q) ||
      (role.isNotEmpty && role.contains(q)) ||
      (rawRole.isNotEmpty && rawRole.contains(q));
}

List<ChatV1MentionPerson> filterMentionPeople(
  List<ChatV1MentionPerson> people,
  String query,
) {
  return people.where((p) => chatMentionMatches(p, query)).toList();
}

/// Token the server can resolve. First name by default (web composer). If two
/// people share that first name, use the compact full name so the match is
/// unique (`mention_token_matches_user` accepts both).
String chatMentionToken(
  ChatV1MentionPerson person,
  List<ChatV1MentionPerson> people,
) {
  final parts = person.name
      .trim()
      .split(_space)
      .where((part) => part.isNotEmpty)
      .toList();
  var token = parts.isEmpty ? 'User' : parts.first;
  final first = token.toLowerCase();
  final collision = people.any((other) {
    if (other.userId == person.userId) return false;
    final otherParts = other.name
        .trim()
        .split(_space)
        .where((part) => part.isNotEmpty)
        .toList();
    if (otherParts.isEmpty) return false;
    return otherParts.first.toLowerCase() == first;
  });
  if (collision && parts.length > 1) {
    token = person.name.trim().replaceAll(_space, '');
  }
  token = token.replaceAll(_tokenBreak, '');
  if (token.isEmpty) token = 'User';
  return '@$token';
}

ChatV1MentionInsertion applyChatMention({
  required String text,
  required ChatV1MentionTrigger trigger,
  required ChatV1MentionPerson person,
  required List<ChatV1MentionPerson> people,
}) {
  var start = trigger.start;
  if (start < 0) start = 0;
  if (start > text.length) start = text.length;
  var end = trigger.end;
  if (end < start) end = start;
  if (end > text.length) end = text.length;
  final token = chatMentionToken(person, people);
  final before = text.substring(0, start);
  final after = text.substring(end);
  final spacer = _leadingSpace.hasMatch(after) ? '' : ' ';
  final next = before + token + spacer + after;
  final skipExisting = spacer.isEmpty && _leadingSpace.hasMatch(after) ? 1 : 0;
  var caret = before.length + token.length + spacer.length + skipExisting;
  if (caret < 0) caret = 0;
  if (caret > next.length) caret = next.length;
  return ChatV1MentionInsertion(text: next, caret: caret);
}

/// One slice of a message body. [isSelf] is only the current user's @name.
class MentionTextSegment {
  final String text;
  final bool isSelf;
  final bool isMention;
  const MentionTextSegment(this.text,
      {this.isSelf = false, this.isMention = false});
}

bool chatTokenMatchesName(String token, String? name) {
  final t = token.trim().toLowerCase();
  final n = (name ?? '').trim().toLowerCase();
  if (t.isEmpty || n.isEmpty) return false;
  final first = n.split(RegExp(r'\s+')).first;
  final compact = n.replaceAll(RegExp(r'\s+'), '');
  return t == n || t == first || t == compact;
}

/// Highlight @CurrentUser only when this message actually mentions them.
List<MentionTextSegment> splitSelfMentionSegments(
  String body, {
  String? currentUserId,
  String? currentUserName,
  List<ChatV1Mention> mentions = const [],
}) {
  final uid = (currentUserId ?? '').trim();
  final self =
      mentions.where((m) => uid.isNotEmpty && m.userId == uid).toList();
  if (self.isEmpty) {
    return [MentionTextSegment(body)];
  }
  final names = <String>[];
  void addName(String? name) {
    final trimmed = (name ?? '').trim();
    if (trimmed.isNotEmpty && !names.contains(trimmed)) names.add(trimmed);
  }

  addName(currentUserName);
  for (final mention in self) {
    addName(mention.name);
  }
  if (names.isEmpty) return [MentionTextSegment(body)];

  final re = RegExp(r'@([^\s@.,!?;:]+)');
  final out = <MentionTextSegment>[];
  var index = 0;
  for (final match in re.allMatches(body)) {
    if (match.start > index) {
      out.add(MentionTextSegment(body.substring(index, match.start)));
    }
    final token = match.group(1) ?? '';
    final mine = names.any((name) => chatTokenMatchesName(token, name));
    out.add(MentionTextSegment(match.group(0)!, isSelf: mine));
    index = match.end;
  }
  if (index < body.length) {
    out.add(MentionTextSegment(body.substring(index)));
  }
  if (out.isEmpty) return [MentionTextSegment(body)];
  return out;
}

/// Display every confirmed tag with its readable name. Unconfirmed @text and
/// email addresses remain plain text; participant names alone do not create tags.
List<MentionTextSegment> splitChatMentionSegments(
  String body, {
  String? currentUserId,
  String? currentUserName,
  List<ChatV1Mention> mentions = const [],
}) {
  final aliases = <String, List<ChatV1Mention>>{};
  final names = <String, String>{};
  for (final mention in mentions) {
    final name = (mention.name ??
            (mention.userId == currentUserId ? currentUserName : null) ??
            '')
        .trim();
    if (name.isEmpty) continue;
    names[mention.userId] = name;
    for (final alias in {
      name,
      name.split(_space).first,
      name.replaceAll(_space, ''),
    }) {
      final key = alias.toLowerCase();
      final people = aliases.putIfAbsent(key, () => []);
      if (!people.any((person) => person.userId == mention.userId)) {
        people.add(mention);
      }
    }
  }
  // A shared first name cannot identify one of several tagged people.
  final keys = aliases.keys.where((key) => aliases[key]!.length == 1).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  if (keys.isEmpty) return [MentionTextSegment(body)];
  final pattern = keys.map(RegExp.escape).join('|');
  final re = RegExp(
    r'(^|[\s(])@(' + pattern + r')(?=$|[\s@.,!?;:)])',
    caseSensitive: false,
  );
  final out = <MentionTextSegment>[];
  var index = 0;
  for (final match in re.allMatches(body)) {
    final start = match.start + match.group(1)!.length;
    if (start > index) {
      out.add(MentionTextSegment(body.substring(index, start)));
    }
    final person = aliases[match.group(2)!.toLowerCase()]!.single;
    out.add(MentionTextSegment(
      '@${names[person.userId]}',
      isMention: true,
      isSelf: person.userId == currentUserId,
    ));
    index = match.end;
  }
  if (index < body.length) out.add(MentionTextSegment(body.substring(index)));
  return out.isEmpty ? [MentionTextSegment(body)] : out;
}
