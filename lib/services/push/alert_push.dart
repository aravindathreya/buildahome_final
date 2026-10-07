import 'dart:convert';

/// Turns an existing in-app alert into the data payload a push can carry.
class AlertPushMapper {
  static const Set<String> secretKeys = {
    'api_token',
    'token',
    'password',
    'otp',
    'phone',
    'email',
    'authorization',
    'cookie',
    'session',
  };

  static const List<String> navigationKeys = [
    'id',
    'title',
    'body',
    'type',
    'category',
    'notification_type',
    'screen',
    'native_screen',
    'open_tab',
    'wf_native_screen',
    'redirect_page',
    'redirect_url',
    'url',
    'link',
    'deep_link',
    'task_id',
    'erp_task_id',
    'workflow_task_id',
    'focus_task_id',
    'project_id',
    'project_name',
    'client_name',
    'indent_id',
    'conversation_id',
    'payment_id',
    'bill_id',
    'po_id',
    'payment_name',
    'bill_name',
    'sender_id',
    'sender_name',
    'message_id',
  ];

  static Map<String, String> toData(Map<String, dynamic> alert) {
    final out = <String, String>{};
    for (final key in navigationKeys) {
      if (secretKeys.contains(key)) continue;
      final value = alert[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isEmpty || text.toLowerCase() == 'null') continue;
      out[key] = (key == 'body' || key == 'title') ? clip(text, 180) : text;
    }
    out.putIfAbsent('type', () {
      final fallback = alert['notification_type'] ?? alert['category'] ?? 'alert';
      return fallback.toString();
    });
    return out;
  }

  /// Alerts that arrived after a previous sync in this process.
  static List<Map<String, dynamic>> selectNewAlerts({
    required bool hadBaseline,
    required Set<String> previousFingerprints,
    required List<Map<String, dynamic>> next,
    required String Function(Map<String, dynamic> alert) fingerprint,
    required bool Function(Map<String, dynamic> alert) isUnread,
  }) {
    if (!hadBaseline) return const [];
    final fresh = <Map<String, dynamic>>[];
    for (final alert in next) {
      if (!isUnread(alert)) continue;
      if (previousFingerprints.contains(fingerprint(alert))) continue;
      fresh.add(alert);
    }
    return fresh;
  }

  static String clip(String value, int max) {
    final singleLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.length <= max) return singleLine;
    if (max <= 3) return singleLine.substring(0, max);
    return '${singleLine.substring(0, max - 3)}...';
  }
}

/// Session-scoped ids so a polled alert and its FCM copy show once.
class ShownPushRegistry {
  final Set<String> _keys = <String>{};

  bool claim(String key) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return false;
    return _keys.add(trimmed);
  }

  void clear() => _keys.clear();
}

/// Holds a tap that arrived before login / the first frame (terminated launch).
class PushLaunchQueue {
  Map<String, String>? _pending;
  bool ready = false;

  void stage(Map<String, String> data) {
    if (data.isEmpty) return;
    _pending = Map<String, String>.from(data);
  }

  Map<String, String>? take() {
    if (!ready) return null;
    final value = _pending;
    _pending = null;
    return value;
  }

  void reset() {
    _pending = null;
    ready = false;
  }
}

class AlertPushInbox {
  static void Function(List<Map<String, dynamic>> alerts)? onDeliver;

  static void deliver(List<Map<String, dynamic>> alerts) {
    if (alerts.isEmpty) return;
    onDeliver?.call(alerts);
  }
}

Map<String, String> normalizePushData(Map<String, dynamic> raw) {
  final expanded = <String, dynamic>{};
  raw.forEach((key, value) {
    if (key == 'payload' && value is String && value.trim().startsWith('{')) {
      try {
        final nested = jsonDecode(value);
        if (nested is Map) {
          nested.forEach((nestedKey, nestedValue) {
            expanded['$nestedKey'] = nestedValue;
          });
          return;
        }
      } catch (_) {}
    }
    expanded[key] = value;
  });

  final out = <String, String>{};
  expanded.forEach((key, value) {
    if (AlertPushMapper.secretKeys.contains(key.toLowerCase())) return;
    if (value == null) return;
    final text = value.toString().trim();
    if (text.isEmpty || text.toLowerCase() == 'null') return;
    if (key == 'body' || key == 'title' || key == 'preview') {
      out[key] = AlertPushMapper.clip(text, 180);
    } else {
      out[key] = text;
    }
  });
  return out;
}
