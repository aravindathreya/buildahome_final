import 'package:flutter/material.dart';

import 'chat_v1_models.dart';
import 'chat_v1_theme.dart';

/// Shared helpers for Chat V1 (no mock seeds).
class ChatV1Utils {
  ChatV1Utils._();

  /// Preferred display titles + sort order when the API returns that channel.
  /// Do not use this list to invent/placeholder channels the user is not in.
  static const List<String> channelTitles = [
    'General',
    'Internal',
    'Architectural',
    'MEP',
    'Update and Doc',
    'QA / QC',
    'Sales Weekly updates',
    'Architect weekly updates',
  ];

  /// Legacy titles that map to "Update and Doc".
  static const List<String> updateAndDocAliases = [
    'Update and Doc',
    'DOC / NT',
    'Upgrade/DOC',
    'DOC/NT',
    'DOC NT',
    'Upgrade / DOC',
  ];

  static int channelSortIndex(String title) {
    final canonical = canonicalChannelTitle(title);
    final n = _normalizeTitle(canonical);
    for (var i = 0; i < channelTitles.length; i++) {
      final tn = _normalizeTitle(channelTitles[i]);
      if (n == tn || n.startsWith('$tn ')) return i;
    }
    return 999;
  }

  static bool isKnownChannelTitle(String title) {
    if (isUpdateAndDocChannel(title)) return true;
    final n = _normalizeTitle(title);
    for (final t in channelTitles) {
      final tn = _normalizeTitle(t);
      if (n == tn || n.startsWith('$tn ')) return true;
    }
    return false;
  }

  static bool isUpdateAndDocChannel(String title) {
    final n = _normalizeTitle(title);
    return n == 'update and doc' ||
        n == 'doc nt' ||
        n == 'upgrade doc' ||
        n == 'docnt';
  }

  /// Display / sort title for known channels (aliases → canonical label).
  static String canonicalChannelTitle(String title) {
    if (isUpdateAndDocChannel(title)) return 'Update and Doc';
    final n = _normalizeTitle(title);
    for (final t in channelTitles) {
      final tn = _normalizeTitle(t);
      if (n == tn || n.startsWith('$tn ')) return t;
    }
    return title;
  }

  static String _normalizeTitle(String title) {
    return title
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static IconData channelIcon(String title) {
    switch (_normalizeTitle(canonicalChannelTitle(title))) {
      case 'general':
        return Icons.tag_rounded;
      case 'internal':
        return Icons.lock_outline_rounded;
      case 'architectural':
        return Icons.architecture_rounded;
      case 'mep':
        return Icons.electrical_services_rounded;
      case 'update and doc':
        return Icons.description_outlined;
      case 'qa qc':
        return Icons.verified_outlined;
      case 'sales weekly updates':
        return Icons.trending_up_rounded;
      case 'architect weekly updates':
        return Icons.calendar_view_week_rounded;
      default:
        return Icons.forum_outlined;
    }
  }

  static Color channelAccent(String title) {
    switch (_normalizeTitle(canonicalChannelTitle(title))) {
      case 'general':
        return ChatV1Theme.accent;
      case 'internal':
        return const Color(0xFF3B82F6);
      case 'architectural':
        return const Color(0xFF8B5CF6);
      case 'mep':
        return const Color(0xFFEF4444);
      case 'update and doc':
        return const Color(0xFF0EA5E9);
      case 'qa qc':
        return ChatV1Theme.completed;
      case 'sales weekly updates':
        return const Color(0xFF14B8A6);
      case 'architect weekly updates':
        return const Color(0xFFA855F7);
      default:
        return const Color(0xFF64748B);
    }
  }

  static String initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final s = parts.first;
      return s.length >= 2 ? s.substring(0, 2).toUpperCase() : s.toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  static Color colorForId(String id) {
    const palette = <Color>[
      Color(0xFF2ECC71),
      Color(0xFF3B82F6),
      Color(0xFFF59E0B),
      Color(0xFFEF4444),
      Color(0xFF8B5CF6),
      Color(0xFF14B8A6),
      Color(0xFF0EA5E9),
      Color(0xFFA855F7),
    ];
    final hash = id.codeUnits.fold<int>(0, (a, b) => a + b);
    return palette[hash % palette.length];
  }

  static String timeAgo(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    if (d.inDays < 7) return '${d.inDays}d';
    return '${dt.day}/${dt.month}';
  }

  static String clock(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m ${dt.hour >= 12 ? 'PM' : 'AM'}';
  }

  static String dateLabel(DateTime dt) {
    final today = DateTime.now();
    final a = DateTime(dt.year, dt.month, dt.day);
    final b = DateTime(today.year, today.month, today.day);
    final diff = b.difference(a).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  static DateTime? parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString());
  }

  /// Indian-style amount: ₹1,25,000
  static String formatInr(num amount) {
    final n = amount.round();
    final neg = n < 0;
    var s = n.abs().toString();
    if (s.length <= 3) return '${neg ? '-' : ''}₹$s';
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${neg ? '-' : ''}₹${parts.join(',')},$last3';
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Short text for reply quotes / composer banner.
  static String replySnippet(ChatV1Message msg) {
    final body = msg.body.trim();
    final lower = body.toLowerCase();
    if (body.isNotEmpty &&
        !lower.startsWith('uploaded:') &&
        lower != 'attachment' &&
        lower != 'this message was deleted') {
      return body;
    }
    if (lower.startsWith('uploaded:')) {
      final name = body.substring(body.indexOf(':') + 1).trim();
      if (name.isNotEmpty) return name;
    }
    if (msg.attachments.isNotEmpty) {
      final att = msg.attachments.first;
      final name = att.fileName.trim();
      if (att.isImage) return name.isNotEmpty ? name : 'Photo';
      if (att.isPdf) return name.isNotEmpty ? name : 'PDF';
      if (name.isNotEmpty) return name;
    }
    final fileName = (msg.fileName ?? '').trim();
    if (fileName.isNotEmpty) return fileName;
    switch (msg.type) {
      case ChatV1MsgType.image:
        return 'Photo';
      case ChatV1MsgType.pdf:
        return 'PDF';
      case ChatV1MsgType.video:
        return 'Video';
      case ChatV1MsgType.document:
        return 'Document';
      default:
        return body.isNotEmpty ? body : 'Message';
    }
  }

  static String formatReplyPreview({
    required String authorName,
    required String snippet,
  }) {
    final author = authorName.trim().isEmpty ? 'Someone' : authorName.trim();
    final text = snippet.trim().isEmpty ? 'Message' : snippet.trim();
    return '$author: $text';
  }

  /// True when the preview is empty or a useless generic like "X: Attachment".
  static bool isWeakReplyPreview(String? preview) {
    if (preview == null) return true;
    final t = preview.trim();
    if (t.isEmpty) return true;
    final lower = t.toLowerCase();
    if (lower == 'attachment' ||
        lower == 'message' ||
        lower == 'uploaded:' ||
        lower.endsWith(': attachment') ||
        lower.endsWith(': message')) {
      return true;
    }
    return false;
  }

  /// Make attachment/media paths loadable in Image.network / url_launcher.
  static String resolveMediaUrl(String path, {String? baseUrl}) {
    final raw = path.trim();
    if (raw.isEmpty) return raw;
    if (raw.startsWith('http://') ||
        raw.startsWith('https://') ||
        raw.startsWith('blob:') ||
        raw.startsWith('data:')) {
      return raw;
    }
    final base = (baseUrl ?? 'https://office.buildahome.in').replaceAll(
      RegExp(r'/+$'),
      '',
    );
    if (raw.startsWith('/')) return '$base$raw';
    return '$base/$raw';
  }

  static String formatAbsolute(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, ${clock(dt)}';
  }
}
