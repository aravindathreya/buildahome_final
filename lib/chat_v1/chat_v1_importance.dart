/// First-line captions for "Mark as important" (web + phone).
class ChatV1Importance {
  final String kind;
  final String channel;
  final String by;
  final String body;

  const ChatV1Importance({
    required this.kind,
    required this.channel,
    required this.by,
    required this.body,
  });

  static final _mark = RegExp(r'^Marked as important(?: · (.+))?$');
  static final _sharedDot = RegExp(r'^Shared from (.+?) · (.+)$');
  static final _sharedBy = RegExp(r'^Shared from (.+?) by (.+)$');
  static final _shared = RegExp(r'^Shared from (.+)$');

  static ChatV1Importance parse(String raw) {
    final text = raw;
    final nl = text.indexOf('\n');
    final first = (nl == -1 ? text : text.substring(0, nl)).trimRight();
    final rest = nl == -1 ? '' : text.substring(nl + 1);
    final mark = _mark.firstMatch(first);
    if (mark != null) {
      return ChatV1Importance(
        kind: 'marked',
        channel: '',
        by: (mark.group(1) ?? '').trim(),
        body: rest,
      );
    }
    final dot = _sharedDot.firstMatch(first);
    if (dot != null) {
      return ChatV1Importance(
        kind: 'shared',
        channel: (dot.group(1) ?? '').trim(),
        by: (dot.group(2) ?? '').trim(),
        body: rest,
      );
    }
    final byLine = _sharedBy.firstMatch(first);
    if (byLine != null) {
      return ChatV1Importance(
        kind: 'shared',
        channel: (byLine.group(1) ?? '').trim(),
        by: (byLine.group(2) ?? '').trim(),
        body: rest,
      );
    }
    final shared = _shared.firstMatch(first);
    if (shared != null) {
      return ChatV1Importance(
        kind: 'shared',
        channel: (shared.group(1) ?? '').trim(),
        by: '',
        body: rest,
      );
    }
    return ChatV1Importance(kind: '', channel: '', by: '', body: text);
  }
}