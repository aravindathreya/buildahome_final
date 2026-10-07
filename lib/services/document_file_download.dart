import 'package:flutter/material.dart';

import '../models/workflow_document.dart';
import 'authenticated_document_fetcher.dart';
import 'document_file_share_stub.dart'
    if (dart.library.io) 'document_file_share_io.dart';

/// Downloads a project file when the office web allows this user to.
Future<void> downloadWorkflowDocument(
  BuildContext context,
  WorkflowDocumentUpload document,
) async {
  if (!document.canDownload || !document.hasUrl) return;

  final navigator = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);
  var dialogOpen = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Preparing download…'),
            ],
          ),
        ),
      ),
    ),
  );

  try {
    final fetch = await AuthenticatedDocumentFetcher.instance.fetch(
      url: document.url!,
      documentId: document.id,
      contentTypeHint: document.contentType,
      isPdfHint: document.isPdf,
      isImageHint: document.isImage,
    );
    if (dialogOpen && navigator.canPop()) {
      navigator.pop();
      dialogOpen = false;
    }
    final bytes = fetch.bytes;
    if (!context.mounted) return;
    if (bytes == null || bytes.isEmpty || _downloadBlocked(fetch.kind)) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            fetch.userMessage.isNotEmpty
                ? fetch.userMessage
                : 'Unable to download this document.',
          ),
        ),
      );
      return;
    }
    final box = context.findRenderObject();
    final origin = box is RenderBox && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    await shareDocumentBytes(
      bytes: bytes,
      fileName: documentDownloadFileName(document, fetch.contentType),
      mimeType: fetch.contentType.trim().isEmpty ? null : fetch.contentType,
      sharePositionOrigin: origin,
    );
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Unable to download this document.')),
    );
  } finally {
    if (dialogOpen && navigator.canPop()) {
      navigator.pop();
    }
  }
}

bool _downloadBlocked(DocumentPayloadKind kind) {
  return kind == DocumentPayloadKind.loginHtml ||
      kind == DocumentPayloadKind.sessionExpired ||
      kind == DocumentPayloadKind.missing ||
      kind == DocumentPayloadKind.networkError;
}

/// File name used when the user saves the document.
String documentDownloadFileName(
  WorkflowDocumentUpload document,
  String contentType,
) {
  var name = document.name.trim();
  if (name.isEmpty) name = document.displayTitle.trim();
  name = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  if (name.isEmpty) name = 'document';
  if (!name.contains('.')) {
    final ext = _extensionFor(document, contentType);
    if (ext.isNotEmpty) name = '$name.$ext';
  }
  if (name.length > 120) {
    final dot = name.lastIndexOf('.');
    if (dot > 0 && name.length - dot <= 8) {
      final ext = name.substring(dot);
      name = '${name.substring(0, 120 - ext.length)}$ext';
    } else {
      name = name.substring(0, 120);
    }
  }
  return name;
}

String _extensionFor(WorkflowDocumentUpload document, String contentType) {
  final urlName = (document.url ?? '').split('?').first;
  final slash = urlName.lastIndexOf('/');
  final leaf = slash >= 0 ? urlName.substring(slash + 1) : urlName;
  final dot = leaf.lastIndexOf('.');
  if (dot > 0 && leaf.length - dot <= 8) {
    return leaf.substring(dot + 1).toLowerCase();
  }
  final mime = contentType.toLowerCase();
  if (document.isPdf || mime.contains('pdf')) return 'pdf';
  if (mime.contains('png')) return 'png';
  if (mime.contains('webp')) return 'webp';
  if (mime.contains('jpeg') || mime.contains('jpg') || document.isImage) {
    return 'jpg';
  }
  return '';
}
