import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../chat_v1/chat_v1_utils.dart';
import '../models/workflow_document.dart';
import '../services/authenticated_document_fetcher.dart';
import '../services/document_file_share_stub.dart'
    if (dart.library.io) '../services/document_file_share_io.dart';
import 'in_app_video_player.dart';
import 'workflow_document_viewer.dart';

/// A slice of message text, either plain copy or a tappable URL.
class PlainTextLink {
  const PlainTextLink(this.text, {this.isLink = false});

  final String text;
  final bool isLink;
}

/// Splits [text] into plain runs and `http(s)` links.
/// Trailing punctuation stays outside the link.
List<PlainTextLink> splitPlainTextLinks(String text) {
  final matches = RegExp(r'https?:\/\/\S+', caseSensitive: false).allMatches(text);
  if (matches.isEmpty) return [PlainTextLink(text)];

  final out = <PlainTextLink>[];
  var start = 0;
  for (final match in matches) {
    if (match.start > start) {
      out.add(PlainTextLink(text.substring(start, match.start)));
    }
    var raw = match.group(0) ?? '';
    var trail = '';
    while (raw.isNotEmpty && '.,;:!?)]}'.contains(raw[raw.length - 1])) {
      trail = raw[raw.length - 1] + trail;
      raw = raw.substring(0, raw.length - 1);
    }
    if (raw.isNotEmpty) out.add(PlainTextLink(raw, isLink: true));
    if (trail.isNotEmpty) out.add(PlainTextLink(trail));
    start = match.end;
  }
  if (start < text.length) out.add(PlainTextLink(text.substring(start)));
  return out;
}

class SharedDocumentOpenPlan {
  const SharedDocumentOpenPlan({
    required this.url,
    required this.displayName,
    required this.contentType,
    required this.inApp,
  });

  final String url;
  final String displayName;
  final String contentType;

  /// PDFs, images, and private office files open in the app viewer.
  /// Other links stay in the browser.
  final bool inApp;
}

SharedDocumentOpenPlan planSharedDocumentOpen({
  required String url,
  String fileName = '',
  String contentType = '',
}) {
  final resolved = ChatV1Utils.resolveMediaUrl(url.trim());
  final name = fileName.trim().isEmpty ? _nameFromUrl(resolved) : fileName.trim();
  final http = resolved.startsWith('http://') || resolved.startsWith('https://');
  if (!http) {
    return SharedDocumentOpenPlan(
      url: '',
      displayName: name.isEmpty ? 'Document' : name,
      contentType: contentType,
      inApp: false,
    );
  }

  final mime = contentType.trim().toLowerCase();
  final pdf = _looksLikePdf(resolved, name, mime);
  final image = _looksLikeImage(resolved, name, mime);
  final office = _looksLikeOffice(resolved, name, mime);
  final video = looksLikeVideoFile(url: resolved, name: name, contentType: mime);
  final audio = looksLikeAudioFile(url: resolved, name: name, contentType: mime);
  final text = _looksLikePlainText(resolved, name, mime);
  final svg = _looksLikeSvg(resolved, name, mime);
  final private = AuthenticatedDocumentFetcher.classifyUrl(resolved) ==
      DocumentUrlProfile.buildahomePrivate;
  final inApp = !svg && (pdf || image || office || text || private);

  var resolvedType = contentType.trim();
  if (svg) {
    resolvedType = 'image/svg+xml';
  } else if (pdf || (private && !image && !office && !video && !audio && !text)) {
    resolvedType = 'application/pdf';
  } else if (image) {
    resolvedType = mime.startsWith('image/') ? contentType.trim() : 'image/jpeg';
  } else if (office) {
    resolvedType = mime.isNotEmpty ? contentType.trim() : resolvedType;
  } else if (resolvedType == 'application/octet-stream') {
    resolvedType = '';
  }

  return SharedDocumentOpenPlan(
    url: resolved,
    displayName: name.isEmpty ? 'Document' : name,
    contentType: resolvedType,
    inApp: inApp,
  );
}

/// Opens a chat or assistant file in the app when it can be previewed.
/// Plain web links open in the browser.
Future<void> openSharedDocument(
  BuildContext context, {
  required String url,
  String fileName = '',
  String contentType = '',
  bool clientMode = false,
  /// When true, document-like URLs always use the in-app viewer even if
  /// [planSharedDocumentOpen] would otherwise treat them as browser links.
  bool forceInApp = false,
}) async {
  final plan = planSharedDocumentOpen(
    url: url,
    fileName: fileName,
    contentType: contentType,
  );
  if (plan.url.isEmpty) {
    _toast(context, 'Document not available yet');
    return;
  }

  if (looksLikeAudioFile(
      url: plan.url, name: plan.displayName, contentType: contentType)) {
    await openInAppAudio(context, url: plan.url, title: plan.displayName);
    return;
  }

  if (looksLikeVideoFile(
      url: plan.url, name: plan.displayName, contentType: contentType)) {
    await openInAppVideo(context, url: plan.url, title: plan.displayName);
    return;
  }

  // SVG cannot be drawn by the in-app image viewer: hand it to another app.
  if (_looksLikeSvg(plan.url, plan.displayName, contentType.toLowerCase())) {
    final prepared =
        await AuthenticatedDocumentFetcher.instance.fetch(url: plan.url);
    final bytes = prepared.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      try {
        await shareDocumentBytes(
          bytes: bytes,
          fileName: plan.displayName.toLowerCase().endsWith('.svg')
              ? plan.displayName
              : '${plan.displayName}.svg',
          mimeType: 'image/svg+xml',
        );
        return;
      } catch (_) {}
    }
  }

  final useInApp = plan.inApp || forceInApp;
  if (useInApp) {
    final document = WorkflowDocumentUpload(
      id: 'shared-${plan.url.hashCode}',
      documentKey: 'shared_document',
      name: plan.displayName,
      url: plan.url,
      contentType: plan.contentType.isEmpty ? null : plan.contentType,
      isLatest: true,
    );
    if (!context.mounted) return;
    await openWorkflowDocument(context, document, clientMode: clientMode);
     return;
  }

  final uri = Uri.tryParse(plan.url);
  if (uri == null) {
    _toast(context, 'Could not open this link');
    return;
  }
  try {
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      _toast(context, 'Could not open this link');
    }
  } catch (_) {
    if (context.mounted) _toast(context, 'Could not open this link');
  }
}

bool _looksLikePdf(String url, String name, String mime) {
  if (mime.contains('pdf')) return true;
  final blob = '${_pathOnly(url)} $name'.toLowerCase();
  return blob.contains('.pdf');
}

bool _looksLikeSvg(String url, String name, String mime) {
  if (mime.contains('svg')) return true;
  return _pathOnly(url).toLowerCase().endsWith('.svg') ||
      name.toLowerCase().endsWith('.svg');
}

bool _looksLikePlainText(String url, String name, String mime) {
  if (mime.startsWith('text/plain') ||
      mime.startsWith('text/csv') ||
      mime.contains('json') ||
      mime.startsWith('text/markdown')) {
    return true;
  }
  final path = _pathOnly(url).toLowerCase();
  final lowerName = name.toLowerCase();
  const exts = [
    '.txt', '.csv', '.tsv', '.json', '.xml', '.log', '.md', '.yaml', '.yml',
  ];
  return exts.any((e) => path.endsWith(e) || lowerName.endsWith(e));
}

bool _looksLikeImage(String url, String name, String mime) {
  if (_looksLikeSvg(url, name, mime)) return false;
  if (mime.startsWith('image/')) return true;
  return _hasImageExtension(_pathOnly(url)) || _hasImageExtension(name);
}

bool _looksLikeOffice(String url, String name, String mime) {
  if (mime.contains('msword') ||
      mime.contains('officedocument') ||
      mime.contains('ms-excel') ||
      mime.contains('ms-powerpoint') ||
      mime.contains('opendocument')) {
    return true;
  }
  final path = _pathOnly(url).toLowerCase();
  final lowerName = name.toLowerCase();
  bool has(String ext) => path.endsWith(ext) || lowerName.endsWith(ext);
  return has('.doc') ||
      has('.docx') ||
      has('.docm') ||
      has('.xls') ||
      has('.xlsx') ||
      has('.xlsm') ||
      has('.ppt') ||
      has('.pptx') ||
      has('.pptm') ||
      has('.pps') ||
      has('.ppsx') ||
      has('.odt') ||
      has('.ods') ||
      has('.odp') ||
      has('.rtf') ||
      has('.txt') ||
      has('.csv');
}

bool _hasImageExtension(String value) {
  final lower = value.toLowerCase();
  return lower.endsWith('.png') ||
      lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.heic') ||
      lower.endsWith('.bmp');
}

String _pathOnly(String url) => url.split('?').first;

String _nameFromUrl(String url) {
  final path = url.split('?').first;
  final slash = path.lastIndexOf('/');
  if (slash < 0 || slash == path.length - 1) return '';
  return Uri.decodeComponent(path.substring(slash + 1));
}

void _toast(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
