import 'dart:io';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// iOS draws PDFs inside the web view and shows page 1 before the download
/// finishes. Android's web view cannot draw PDFs, so it keeps the file renderer.
bool preferNativePdfStream() => Platform.isIOS;

Widget buildNativePdfView({
  required String url,
  required Map<String, String> headers,
}) {
  if (!Platform.isIOS) return const SizedBox.shrink();
  return _IosPdfView(url: url, headers: headers);
}

Widget? buildCachedPdfView(List<int> bytes) => null;

class _IosPdfView extends StatefulWidget {
  final String url;
  final Map<String, String> headers;

  const _IosPdfView({
    required this.url,
    required this.headers,
  });

  @override
  State<_IosPdfView> createState() => _IosPdfViewState();
}

class _IosPdfViewState extends State<_IosPdfView> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..loadRequest(Uri.parse(widget.url), headers: widget.headers);
  }

  @override
  Widget build(BuildContext context) {
    return WebViewWidget(controller: _controller);
  }
}
