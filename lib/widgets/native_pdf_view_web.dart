import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart';

/// The browser's own PDF viewer paints the first page while the file is
/// still downloading. That is much faster than parsing the whole file in Dart.
bool preferNativePdfStream() => true;

Widget buildNativePdfView({
  required String url,
  required Map<String, String> headers,
}) {
  return _UrlPdfFrame(url: url);
}

Widget? buildCachedPdfView(List<int> bytes) {
  return _BlobPdfFrame(bytes: bytes);
}

HTMLIFrameElement _pdfFrame(String url) {
  return HTMLIFrameElement()
    ..src = url
    ..style.border = 'none'
    ..style.width = '100%'
    ..style.height = '100%'
    ..allowFullscreen = true;
}

class _UrlPdfFrame extends StatefulWidget {
  final String url;

  const _UrlPdfFrame({required this.url});

  @override
  State<_UrlPdfFrame> createState() => _UrlPdfFrameState();
}

class _UrlPdfFrameState extends State<_UrlPdfFrame> {
  late final String _viewType = 'bah-pdf-url-${identityHashCode(this)}';

  @override
  void initState() {
    super.initState();
    final url = widget.url;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int id) {
      return _pdfFrame(url);
    });
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}

class _BlobPdfFrame extends StatefulWidget {
  final List<int> bytes;

  const _BlobPdfFrame({required this.bytes});

  @override
  State<_BlobPdfFrame> createState() => _BlobPdfFrameState();
}

class _BlobPdfFrameState extends State<_BlobPdfFrame> {
  late final String _viewType = 'bah-pdf-blob-${identityHashCode(this)}';
  String? _blobUrl;

  @override
  void initState() {
    super.initState();
    final data = Uint8List.fromList(widget.bytes).buffer.toJS;
    final blob = Blob(
      [data].toJS,
      BlobPropertyBag(type: 'application/pdf'),
    );
    final url = URL.createObjectURL(blob);
    _blobUrl = url;
    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int id) {
      return _pdfFrame(url);
    });
  }

  @override
  void dispose() {
    final url = _blobUrl;
    if (url != null) URL.revokeObjectURL(url);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
