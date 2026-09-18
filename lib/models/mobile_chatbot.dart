/// Client project Q&A bot payloads from `/API/mobile/chatbot*`.
///
/// This is not `/api/v1/chat` (staff Chat V1).

class MobileChatbotGreeting {
  const MobileChatbotGreeting({
    required this.greeting,
    this.questions = const [],
  });

  static const String fallbackGreeting =
      'Hi! I’m your BuildAHome assistant. Ask me about payments, progress, documents, portal, or how to reach your team.';

  static const List<String> fallbackQuestions = [
    'Where are my payments?',
    'How do I track progress?',
    'Open Client Portal tips',
    'Talk to my project team',
  ];

  static const MobileChatbotGreeting fallback = MobileChatbotGreeting(
    greeting: fallbackGreeting,
    questions: fallbackQuestions,
  );

  final String greeting;
  final List<String> questions;

  factory MobileChatbotGreeting.fromJson(Map<String, dynamic> json) {
    final root = _unwrapData(json);
    final greeting = _firstNonEmpty([
      root['greeting'],
      root['welcome'],
      root['welcome_message'],
      root['intro'],
      root['answer'],
      root['text'],
      root['message'],
    ]);
    return MobileChatbotGreeting(
      greeting: greeting.isEmpty ? fallbackGreeting : greeting,
      questions: _stringList(root, const [
        'questions',
        'chips',
        'suggestions',
        'quick_replies',
        'sample_questions',
        'suggested_questions',
        'prompts',
      ]),
    );
  }
}

class MobileChatbotStageImage {
  const MobileChatbotStageImage({
    required this.url,
    this.caption = '',
    this.kind = 'image',
  });

  final String url;
  final String caption;
  final String kind;

  bool get isVisual =>
      kind.isEmpty ||
      kind == 'image' ||
      kind == 'photo' ||
      kind == 'picture' ||
      kind == 'thumbnail';

  factory MobileChatbotStageImage.fromJson(Map<String, dynamic> json) {
    final url = _resolveMediaUrl(_firstNonEmpty([
      json['url'],
      json['src'],
      json['image'],
      json['image_url'],
      json['path'],
    ]));
    return MobileChatbotStageImage(
      url: url,
      caption: _asString(json['caption']).isNotEmpty
          ? _asString(json['caption'])
          : _asString(json['title']),
      kind: _asString(json['kind']).toLowerCase(),
    );
  }
}

class MobileChatbotTracker {
  const MobileChatbotTracker({
    this.label = '',
    this.percent,
  });

  final String label;

  /// 0–100 when the API sent a completion value.
  final double? percent;

  bool get hasContent => label.isNotEmpty || percent != null;

  factory MobileChatbotTracker.fromJson(dynamic raw) {
    if (raw == null) return const MobileChatbotTracker();
    if (raw is String) {
      return MobileChatbotTracker(label: raw.trim());
    }
    if (raw is num) {
      return MobileChatbotTracker(percent: _percentFrom(raw));
    }
    if (raw is! Map) return const MobileChatbotTracker();
    final json = Map<String, dynamic>.from(raw);
    final percent = _percentFrom(
      json['percent'] ??
          json['percentage'] ??
          json['progress'] ??
          json['completion'] ??
          json['pct'] ??
          json['value'],
    );
    final label = _firstNonEmpty([
      json['label'],
      json['text'],
      json['name'],
      json['current'],
      json['current_activity'],
      json['status'],
    ]);
    return MobileChatbotTracker(label: label, percent: percent);
  }
}

class MobileChatbotStage {
  const MobileChatbotStage({
    required this.name,
    this.images = const [],
    this.tracker = const MobileChatbotTracker(),
  });

  final String name;
  final List<MobileChatbotStageImage> images;
  final MobileChatbotTracker tracker;

  bool get hasContent =>
      name.isNotEmpty || images.isNotEmpty || tracker.hasContent;

  List<String> get imageUrls =>
      images.where((image) => image.isVisual && image.url.isNotEmpty)
          .map((image) => image.url)
          .toList();

  factory MobileChatbotStage.fromJson(Map<String, dynamic> json) {
    final images = <MobileChatbotStageImage>[];
    final rawImages = json['images'] ?? json['photos'] ?? json['media'];
    if (rawImages is List) {
      for (final item in rawImages) {
        if (item is String) {
          final url = _resolveMediaUrl(item);
          if (url.isEmpty) continue;
          images.add(MobileChatbotStageImage(url: url));
        } else if (item is Map) {
          final image = MobileChatbotStageImage.fromJson(
            Map<String, dynamic>.from(item),
          );
          if (image.url.isEmpty) continue;
          images.add(image);
        }
      }
    }

    var tracker = MobileChatbotTracker.fromJson(json['tracker']);
    if (!tracker.hasContent) {
      tracker = MobileChatbotTracker(
        label: _firstNonEmpty([
          json['current_activity'],
          json['activity'],
          json['status'],
        ]),
        percent: _percentFrom(
          json['percent'] ?? json['percentage'] ?? json['progress'],
        ),
      );
    }

    return MobileChatbotStage(
      name: _firstNonEmpty([json['name'], json['title'], json['stage']]),
      images: images,
      tracker: tracker,
    );
  }
}

class MobileChatbotAskResult {
  const MobileChatbotAskResult({
    required this.success,
    required this.supported,
    required this.text,
    this.conversation,
    this.stage,
    this.intent = '',
  });

  final bool success;
  final bool supported;

  /// Bot bubble copy: `answer` on success, `message` on failure.
  final String text;
  final Map<String, dynamic>? conversation;
  final MobileChatbotStage? stage;
  final String intent;

  factory MobileChatbotAskResult.fromJson(
    Map<String, dynamic> json, {
    int statusCode = 200,
  }) {
    final root = _unwrapData(json);
    final successFlag = _asBool(root['success'] ?? json['success']);
    final okFlag = _asBool(root['ok'] ?? json['ok']);
    final success = successFlag ??
        okFlag ??
        (statusCode >= 200 && statusCode < 300);

    final supported = _asBool(root['supported']) ?? true;
    final conversation = _asMap(root['conversation'] ?? json['conversation']);

    MobileChatbotStage? stage;
    final rawStage = root['stage'] ?? json['stage'];
    if (rawStage is Map) {
      final parsed = MobileChatbotStage.fromJson(
        Map<String, dynamic>.from(rawStage),
      );
      if (parsed.hasContent) stage = parsed;
    }

    final answer = _firstNonEmpty([root['answer'], json['answer']]);
    final message = _firstNonEmpty([
      root['message'],
      json['message'],
      root['error'],
      json['error'],
    ]);

    final text = success
        ? (answer.isNotEmpty
            ? answer
            : (message.isNotEmpty
                ? message
                : 'I could not find an answer for that.'))
        : (message.isNotEmpty
            ? message
            : 'I could not answer that right now.');

    return MobileChatbotAskResult(
      success: success,
      supported: supported,
      text: text,
      conversation: conversation,
      stage: stage,
      intent: _asString(root['intent'] ?? json['intent']),
    );
  }

  static MobileChatbotAskResult failure(String message) {
    return MobileChatbotAskResult(
      success: false,
      supported: true,
      text: message,
    );
  }
}

Map<String, dynamic> _unwrapData(Map<String, dynamic> json) {
  final data = json['data'];
  if (data is Map) return Map<String, dynamic>.from(data);
  return json;
}

Map<String, dynamic>? _asMap(dynamic raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return null;
}

bool? _asBool(dynamic raw) {
  if (raw is bool) return raw;
  if (raw is num) return raw != 0;
  if (raw is String) {
    final value = raw.trim().toLowerCase();
    if (value == 'true' || value == '1' || value == 'yes') return true;
    if (value == 'false' || value == '0' || value == 'no') return false;
  }
  return null;
}

String _asString(dynamic raw) {
  if (raw == null) return '';
  final value = raw.toString().trim();
  if (value.isEmpty || value.toLowerCase() == 'null') return '';
  return value;
}

String _firstNonEmpty(List<dynamic> values) {
  for (final value in values) {
    final text = _asString(value);
    if (text.isNotEmpty) return text;
  }
  return '';
}

List<String> _stringList(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final raw = json[key];
    if (raw is! List) continue;
    final items = <String>[];
    for (final item in raw) {
      if (item is String) {
        final text = item.trim();
        if (text.isNotEmpty) items.add(text);
      } else if (item is Map) {
        final text = _firstNonEmpty([
          item['question'],
          item['text'],
          item['label'],
          item['title'],
          item['prompt'],
        ]);
        if (text.isNotEmpty) items.add(text);
      }
    }
    if (items.isNotEmpty) return items;
  }
  return const [];
}

double? _percentFrom(dynamic raw) {
  if (raw == null) return null;
  num? number;
  if (raw is num) {
    number = raw;
  } else if (raw is String) {
    final cleaned = raw.replaceAll('%', '').trim();
    number = num.tryParse(cleaned);
  }
  if (number == null) return null;
  var value = number.toDouble();
  if (value < 0) return 0;
  if (value <= 1) value *= 100;
  if (value > 100) value = 100;
  return value;
}

String _resolveMediaUrl(String path) {
  final raw = path.trim();
  if (raw.isEmpty) return '';
  if (raw.startsWith('http://') ||
      raw.startsWith('https://') ||
      raw.startsWith('data:')) {
    return raw;
  }
  const base = 'https://office.buildahome.in';
  if (raw.startsWith('/')) return '$base$raw';
  return '$base/$raw';
}
