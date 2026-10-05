import 'chat_v1_mentions.dart';

class _PickedMention {
  final String userId;
  final String token;
  final int start;
  final int end;
  const _PickedMention(this.userId, this.token, this.start, this.end);
}

/// Keeps the picker identity attached to its exact token as the draft is edited.
/// A deleted or edited tag must not notify somebody by guessing their name.
class ChatV1MentionDraft {
  String _text = '';
  bool _usedPicker = false;
  List<_PickedMention> _picked = [];
  static final _tokens = RegExp(r'(?<![A-Za-z0-9_])@[^\s@.,!?;:]+');

  List<int>? get mentionedUserIds {
    if (!_usedPicker) return null; // Retain legacy manual @text compatibility.
    final ids = <int>{};
    for (final tag in _picked) {
      final id = int.tryParse(tag.userId);
      if (id != null && id > 0) ids.add(id);
    }
    return ids.toList();
  }

  void updateText(String next) {
    if (next == _text) return;
    var prefix = 0;
    while (prefix < _text.length &&
        prefix < next.length &&
        _text[prefix] == next[prefix]) {
      prefix++;
    }
    var suffix = 0;
    while (suffix < _text.length - prefix &&
        suffix < next.length - prefix &&
        _text[_text.length - suffix - 1] == next[next.length - suffix - 1]) {
      suffix++;
    }
    final oldEnd = _text.length - suffix;
    final delta = next.length - _text.length;
    final shifted = <_PickedMention>[];
    for (final tag in _picked) {
      if (tag.end <= prefix) {
        shifted.add(tag);
      } else if (tag.start >= oldEnd) {
        shifted.add(_PickedMention(
            tag.userId, tag.token, tag.start + delta, tag.end + delta));
      }
      // An edit overlapping a token removes that association.
    }
    final matches = _tokens.allMatches(next).toList();
    _picked = shifted
        .where((tag) => matches.any((match) =>
            match.start == tag.start &&
            match.end == tag.end &&
            match.group(0) == tag.token))
        .toList();
    _text = next;
    if (next.isEmpty) {
      _picked.clear();
      _usedPicker = false;
    }
  }

  ChatV1MentionInsertion insert({
    required String text,
    required ChatV1MentionTrigger trigger,
    required ChatV1MentionPerson person,
    required List<ChatV1MentionPerson> people,
  }) {
    updateText(text);
    final result = applyChatMention(
        text: text, trigger: trigger, person: person, people: people);
    updateText(result.text);
    final token = chatMentionToken(person, people);
    final start = trigger.start.clamp(0, text.length).toInt();
    _picked
        .add(_PickedMention(person.userId, token, start, start + token.length));
    _usedPicker = true;
    return result;
  }
}
