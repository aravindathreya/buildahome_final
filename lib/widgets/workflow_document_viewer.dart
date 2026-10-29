import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';

import '../app_theme.dart';
import '../models/workflow_document.dart';
import '../services/authenticated_document_fetcher.dart';
import '../services/document_file_download.dart';
import '../services/document_byte_cache.dart';
import '../services/document_file_type.dart';
import '../services/document_file_share_stub.dart'
    if (dart.library.io) '../services/document_file_share_io.dart';
import 'native_pdf_view.dart';
import 'office_fallback_preview.dart';

/// Downloads a file ahead of the tap on platforms that render from bytes.
void warmWorkflowDocument(WorkflowDocumentUpload document) {
  final url = document.url;
  if (url == null || url.trim().isEmpty) return;
  if (document.isImage) return;
  if (document.isPdf && preferNativePdfStream()) return;
  unawaited(
    AuthenticatedDocumentFetcher.instance.prefetch(
      url: url,
      documentId: document.id,
      contentTypeHint: document.contentType,
      isPdfHint: document.isPdf,
      isImageHint: document.isImage,
    ),
  );
}

/// Opens a workflow document. Web and iOS stream the PDF in the platform
/// viewer. Android reuses a saved copy when one exists.
Future<void> openWorkflowDocument(
  BuildContext context,
  WorkflowDocumentUpload document, {
  required bool clientMode,
  List<WorkflowDocumentUpload>? relatedDocuments,
}) async {
  if (!document.hasUrl) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Document not available yet')),
    );
    return;
  }

  warmWorkflowDocument(document);

  await Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => WorkflowDocumentViewerScreen(
        document: document,
        clientMode: clientMode,
      ),
    ),
  );
}

class WorkflowDocumentViewerScreen extends StatefulWidget {
  final WorkflowDocumentUpload document;
  final bool clientMode;

  const WorkflowDocumentViewerScreen({
    super.key,
    required this.document,
    this.clientMode = false,
  });

  @override
  State<WorkflowDocumentViewerScreen> createState() =>
      _WorkflowDocumentViewerScreenState();
}

class _WorkflowDocumentViewerScreenState
    extends State<WorkflowDocumentViewerScreen> {
  bool _loading = true;
  String? _errorMessage;
  DocumentFetchResult? _result;
  PdfControllerPinch? _pdfController;
  int _currentPage = 1;
  int _totalPages = 0;
  bool _fullscreen = false;
  bool _forceBytePdf = false;
  bool _imageFellBack = false;
  String? _nativePdfUrl;
  Map<String, String> _nativeHeaders = const {};
  Uint8List? _cachedPdfBytes;
  String? _networkImageUrl;
  int _loadGen = 0;
  bool _preparingPreview = false;

  /// Original Office file kept for Open with when a PDF preview is shown.
  DocumentFetchResult? _originalOffice;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    if (_fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  Future<void> _loadDocument() async {
    final gen = ++_loadGen;
    setState(() {
      _loading = true;
      _errorMessage = null;
      _result = null;
      _nativePdfUrl = null;
      _cachedPdfBytes = null;
      _networkImageUrl = null;
      _originalOffice = null;
      _preparingPreview = false;
    });

    _pdfController?.dispose();
    _pdfController = null;

    final url = widget.document.url;
    if (url == null || url.trim().isEmpty) {
      if (!mounted || gen != _loadGen) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Document not available yet';
      });
      return;
    }

    if (widget.document.isImage && !_imageFellBack) {
      try {
        final prepared =
            await AuthenticatedDocumentFetcher.instance.prepareRequest(url);
        if (!mounted || gen != _loadGen) return;
        setState(() {
          _loading = false;
          _networkImageUrl = prepared.uri.toString();
        });
      } catch (_) {
        _imageFellBack = true;
        if (mounted && gen == _loadGen) await _loadBytes(gen);
      }
      return;
    }

    if (widget.document.isPdf && !_forceBytePdf && preferNativePdfStream()) {
      final streamed = await _openStreamingPdf(url, gen);
      if (streamed || !mounted || gen != _loadGen) return;
    }

    await _loadBytes(gen);
  }

  Future<bool> _openStreamingPdf(String url, int gen) async {
    final prepared =
        await AuthenticatedDocumentFetcher.instance.prepareRequest(url);
    if (!mounted || gen != _loadGen) return true;

    if (kIsWeb) {
      final cached = await DocumentByteCache.instance.read(prepared.cacheKey);
      if (!mounted || gen != _loadGen) return true;
      if (cached != null && buildCachedPdfView(cached) != null) {
        setState(() {
          _loading = false;
          _cachedPdfBytes = cached;
        });
        return true;
      }
      if (!DocumentByteCache.instance.isStreamable(prepared.cacheKey)) {
        final probe = await AuthenticatedDocumentFetcher.instance.probe(
          prepared,
          allowHeaders: false,
        );
        if (!mounted || gen != _loadGen) return true;
        if (probe.blockNative) {
          setState(() {
            _loading = false;
            _errorMessage = probe.message.isEmpty
                ? 'Unable to open this document right now.'
                : probe.message;
          });
          return true;
        }
        if (!probe.canStream) return false;
      }
    }

    setState(() {
      _loading = false;
      _nativePdfUrl = prepared.uri.toString();
      _nativeHeaders = prepared.headers;
    });
    if (!kIsWeb) unawaited(_guardNativePdf(prepared, gen));
    return true;
  }

  Future<void> _guardNativePdf(
    PreparedDocumentRequest prepared,
    int gen,
  ) async {
    final probe = await AuthenticatedDocumentFetcher.instance.probe(
      prepared,
      allowHeaders: true,
    );
    if (!mounted || gen != _loadGen || _nativePdfUrl == null) return;
    if (!probe.blockNative) return;
    setState(() {
      _nativePdfUrl = null;
      _loading = false;
      _errorMessage = probe.message.isEmpty
          ? 'Unable to open this document right now.'
          : probe.message;
    });
  }

  static const _officeExtensions = {
    '.doc', '.docx', '.docm', '.xls', '.xlsx', '.xlsm', '.ppt', '.pptx',
    '.pptm', '.pps', '.ppsx', '.odt', '.ods', '.odp', '.rtf',
  };

  String _fileExtension() {
    String extOf(String value) {
      final v = value.split('?').first.toLowerCase().trim();
      final slash = v.lastIndexOf('/');
      final dot = v.lastIndexOf('.');
      return dot > slash && dot >= 0 ? v.substring(dot) : '';
    }

    final fromName = extOf(widget.document.displayTitle);
    if (_officeExtensions.contains(fromName)) return fromName;
    final fromUrl = extOf(widget.document.url ?? '');
    return fromUrl.isNotEmpty ? fromUrl : fromName;
  }

  bool _isOfficeDocument() => _officeExtensions.contains(_fileExtension());

  /// Asks our server for a PDF rendering of an Office file (`?as=pdf`).
  Future<DocumentFetchResult?> _fetchOfficePdf() async {
    try {
      final url = widget.document.url!.trim();
      final uri = Uri.parse(url);
      final pdfUrl = uri.replace(
        queryParameters: {...uri.queryParameters, 'as': 'pdf'},
      ).toString();
      final result = await AuthenticatedDocumentFetcher.instance.fetch(
        url: pdfUrl,
        documentId: widget.document.id,
        contentTypeHint: 'application/pdf',
        isPdfHint: true,
      );
      if (result.kind == DocumentPayloadKind.pdf && result.bytes != null) {
        return result;
      }
    } catch (e) {
      debugPrint('[DocumentViewer] Office PDF preview failed: $e');
    }
    return null;
  }

  Future<void> _loadBytes(int gen) async {
    var fetch = await AuthenticatedDocumentFetcher.instance.fetch(
      url: widget.document.url!,
      documentId: widget.document.id,
      contentTypeHint: widget.document.contentType,
      isPdfHint: widget.document.isPdf,
      isImageHint: widget.document.isImage,
    );

    if (!mounted || gen != _loadGen) return;

    if (fetch.kind == DocumentPayloadKind.unsupported &&
        fetch.bytes != null &&
        _isOfficeDocument()) {
      _originalOffice = fetch;
      setState(() => _preparingPreview = true);
      final converted = await _fetchOfficePdf();
      if (!mounted || gen != _loadGen) return;
      _preparingPreview = false;
      if (converted != null) fetch = converted;
    }

    if (!fetch.isSuccess || fetch.bytes == null) {
      setState(() {
        _loading = false;
        _errorMessage = fetch.userMessage.isNotEmpty
            ? fetch.userMessage
            : 'Unable to open this document right now.';
        _result = fetch;
      });
      return;
    }

    if (fetch.kind == DocumentPayloadKind.pdf) {
      final fastView = buildCachedPdfView(fetch.bytes!);
      if (fastView != null) {
        setState(() {
          _loading = false;
          _result = fetch;
          _cachedPdfBytes = fetch.bytes;
        });
        return;
      }
      try {
        final doc = await PdfDocument.openData(fetch.bytes!);
        final controller = PdfControllerPinch(document: Future.value(doc));
        if (!mounted || gen != _loadGen) {
          controller.dispose();
          return;
        }
        setState(() {
          _loading = false;
          _result = fetch;
          _pdfController = controller;
          _currentPage = 1;
          _totalPages = doc.pagesCount;
        });
        return;
      } catch (e) {
        debugPrint('[DocumentViewer] PdfDocument.openData failed: $e');
        setState(() {
          _loading = false;
          _errorMessage = 'Unable to open this document right now.';
          _result = fetch;
        });
        return;
      }
    }

    setState(() {
      _loading = false;
      _result = fetch;
    });
  }

  static const _textExtensions = {
    '.txt', '.csv', '.tsv', '.json', '.xml', '.log', '.md', '.html', '.htm',
    '.yaml', '.yml', '.ini', '.conf', '.sql',
  };

  /// No NUL bytes and almost no control characters in the first 4 KB.
  bool _bytesLookLikeText(Uint8List bytes) {
    if (bytes.isEmpty) return false;
    final n = bytes.length < 4096 ? bytes.length : 4096;
    var control = 0;
    for (var i = 0; i < n; i++) {
      final b = bytes[i];
      if (b == 0) return false;
      if (b < 0x09 || (b > 0x0D && b < 0x20)) control++;
    }
    return control * 50 < n;
  }

  String _decodeText(Uint8List bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  bool _looksLikeText(Uint8List bytes) {
    final name = widget.document.displayTitle.toLowerCase();
    final path = (widget.document.url ?? '').split('?').first.toLowerCase();
    final mime = (_result?.contentType ?? widget.document.contentType ?? '')
        .toLowerCase();
    if (mime.startsWith('text/') || mime.contains('json') || mime.contains('csv')) {
      return true;
    }
    if (_textExtensions.any((e) => name.endsWith(e) || path.endsWith(e))) {
      return true;
    }
    if (_isOfficeDocument()) return false;
    final zipOrOle = bytes.length >= 4 &&
        ((bytes[0] == 0x50 && bytes[1] == 0x4B) ||
            (bytes[0] == 0xD0 && bytes[1] == 0xCF));
    return !zipOrOle && _bytesLookLikeText(bytes);
  }

  /// Files without a built-in renderer: text shows here; office, zip and
  /// other formats are downloaded with the app's login and handed to
  /// another app on the phone.
  Widget _buildOtherFile(Uint8List bytes) {
    if (_looksLikeText(bytes)) {
      final text = _decodeText(bytes);
      return ColoredBox(
        color: Colors.white,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            text,
            style: const TextStyle(
              color: Colors.black87,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
          ),
        ),
      );
    }
    final officePreview = buildOfficeFallbackPreview(bytes, _fileExtension());
    if (officePreview != null) {
      return Stack(
        children: [
          Positioned.fill(child: officePreview),
          Positioned(
            right: 16,
            bottom: 16,
            child: SafeArea(
              child: ElevatedButton.icon(
                onPressed: () => shareDocumentBytes(
                  bytes: bytes,
                  fileName: _downloadName(),
                  mimeType: _result?.contentType.isNotEmpty == true
                      ? _result!.contentType
                      : widget.document.contentType,
                ),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open with\u2026'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.navy,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ),
        ],
      );
    }
    return _buildFileCard(bytes);
  }

  /// Card for files the app cannot render (e.g. .dwg): name, type and
  /// actions that hand the real file (with its extension) to other apps.
  Widget _buildFileCard(Uint8List bytes) {
    final fileName = _downloadName();
    final ext = detectDocumentExtension(
      name: fileName,
      url: widget.document.url,
    );
    final mime = _result?.contentType.isNotEmpty == true
        ? _result!.contentType
        : widget.document.contentType;
    void share() {
      final box = context.findRenderObject();
      final origin = box is RenderBox && box.hasSize
          ? box.localToGlobal(Offset.zero) & box.size
          : null;
      shareDocumentBytes(
        bytes: bytes,
        fileName: fileName,
        mimeType: mime,
        sharePositionOrigin: origin,
      );
    }

    final secondary = AppTheme.getTextSecondary(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  ext == 'dwg' || ext == 'dxf'
                      ? Icons.architecture_rounded
                      : Icons.insert_drive_file_outlined,
                  size: 56,
                  color: AppTheme.navy,
                ),
                const SizedBox(height: 16),
                Text(
                  fileName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  documentTypeLabel(ext),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: secondary, fontSize: 14),
                ),
                const SizedBox(height: 12),
                Text(
                  'This file opens in another app on your phone '
                  '(for example an AutoCAD/DWG viewer for drawings).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: secondary, fontSize: 13),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: share,
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('Open in another app'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.navy,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: share,
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('Share / Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _downloadName() {
    final path = (widget.document.url ?? '').split('?').first;
    final slash = path.lastIndexOf('/');
    final fromUrl = slash >= 0 ? Uri.decodeComponent(path.substring(slash + 1)) : '';
    final title = widget.document.displayTitle
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (knownExtensionOf(title).isNotEmpty) return title;
    final ext = detectDocumentExtension(
      name: widget.document.name,
      url: widget.document.url,
    );
    if (title.isEmpty) {
      return fromUrl.isEmpty ? ensureFileExtension('document', ext) : fromUrl;
    }
    return ensureFileExtension(title, ext);
  }

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.document.displayTitle;
    final longTitle = title.length > 28;
    final titleColor = widget.clientMode && _isImage
        ? Colors.white
        : AppTheme.darkTextPrimary;

    return Scaffold(
      backgroundColor: _result?.kind == DocumentPayloadKind.image
          ? Colors.black
          : AppTheme.darkBackgroundPrimary,
      appBar: _fullscreen
          ? null
          : AppBar(
              backgroundColor: widget.clientMode && _isImage
                  ? Colors.black
                  : AppTheme.getBackgroundSecondary(context),
              foregroundColor: titleColor,
              elevation: 0,
              toolbarHeight: longTitle ? 72 : kToolbarHeight,
              title: Text(
                title,
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: titleColor,
                  fontSize: longTitle ? 14 : 16,
                  height: 1.25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              actions: [
                if (_originalOffice?.bytes != null &&
                    _result?.kind == DocumentPayloadKind.pdf)
                  IconButton(
                    icon: const Icon(Icons.open_in_new_rounded),
                    onPressed: () => shareDocumentBytes(
                      bytes: _originalOffice!.bytes!,
                      fileName: _downloadName(),
                      mimeType: _originalOffice!.contentType.isNotEmpty
                          ? _originalOffice!.contentType
                          : widget.document.contentType,
                    ),
                    tooltip: 'Open with\u2026',
                  ),
                if (widget.document.canDownload && widget.document.hasUrl)
                  IconButton(
                    icon: const Icon(Icons.download_rounded),
                    onPressed: () =>
                        downloadWorkflowDocument(context, widget.document),
                    tooltip: 'Download',
                  ),
                if (!_loading && _pdfController != null)
                  IconButton(
                    icon: const Icon(Icons.fullscreen_rounded),
                    onPressed: _toggleFullscreen,
                    tooltip: 'Fullscreen',
                  ),
              ],
            ),
      body: _buildBody(),
    );
  }

  bool get _isImage =>
      _networkImageUrl != null ||
      _result?.kind == DocumentPayloadKind.image;

  Widget _buildBody() {
    if (_loading) {
      if (_preparingPreview) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
              Text(
                'Preparing preview\u2026',
                style: TextStyle(
                  color: AppTheme.getTextSecondary(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      }
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_cachedPdfBytes != null) {
      final view = buildCachedPdfView(_cachedPdfBytes!);
      if (view != null) {
        return ColoredBox(color: Colors.white, child: view);
      }
    }

    if (_nativePdfUrl != null) {
      return ColoredBox(
        color: Colors.white,
        child: buildNativePdfView(
          url: _nativePdfUrl!,
          headers: _nativeHeaders,
        ),
      );
    }

    if (_networkImageUrl != null) {
      return ColoredBox(
        color: Colors.black,
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Image.network(
              _networkImageUrl!,
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              },
              errorBuilder: (_, __, ___) {
                if (!_imageFellBack) {
                  _imageFellBack = true;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _loadDocument();
                  });
                }
                return const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                );
              },
            );
          },
        ),
      );
    }

    if (_result?.kind == DocumentPayloadKind.unsupported &&
        _result?.bytes != null) {
      return _buildOtherFile(_result!.bytes!);
    }

    if (_errorMessage != null) {
      return _ErrorView(
        message: _errorMessage!,
        onRetry: _loadDocument,
      );
    }

    if (_pdfController != null) {
      return ColoredBox(
        color: Colors.white,
        child: Stack(
          fit: StackFit.expand,
          children: [
            PdfViewPinch(
              controller: _pdfController!,
              onPageChanged: (page) {
                if (mounted) setState(() => _currentPage = page);
              },
              builders: PdfViewPinchBuilders<DefaultBuilderOptions>(
                options: const DefaultBuilderOptions(),
                documentLoaderBuilder: (_) =>
                    const Center(child: CircularProgressIndicator()),
                pageLoaderBuilder: (_) =>
                    const Center(child: CircularProgressIndicator()),
                errorBuilder: (_, error) => _ErrorView(
                  message: 'Unable to open this document right now.',
                  onRetry: _loadDocument,
                ),
              ),
            ),
            if (_fullscreen)
              Positioned(
                top: 8,
                right: 8,
                child: SafeArea(
                  child: IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _toggleFullscreen,
                    icon: const Icon(Icons.fullscreen_exit_rounded),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Center(
                child: _PdfPageControls(
                  currentPage: _currentPage,
                  totalPages: _totalPages,
                  controller: _pdfController!,
                  clientMode: widget.clientMode,
                  onFullscreen: _toggleFullscreen,
                  fullscreen: _fullscreen,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_isImage && _result?.bytes != null) {
      return PhotoView(
        imageProvider: MemoryImage(_result!.bytes!),
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 4,
      );
    }

    return _ErrorView(
      message: 'This document format cannot be previewed.',
      onRetry: _loadDocument,
    );
  }
}

class _PdfPageControls extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final PdfControllerPinch controller;
  final bool clientMode;
  final VoidCallback onFullscreen;
  final bool fullscreen;

  const _PdfPageControls({
    required this.currentPage,
    required this.totalPages,
    required this.controller,
    required this.clientMode,
    required this.onFullscreen,
    required this.fullscreen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_left_rounded, color: Colors.white),
            onPressed: currentPage > 1
                ? () => controller.previousPage(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    )
                : null,
          ),
          Text(
            totalPages > 0 ? '$currentPage / $totalPages' : '$currentPage',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chevron_right_rounded, color: Colors.white),
            onPressed: totalPages == 0 || currentPage < totalPages
                ? () => controller.nextPage(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    )
                : null,
          ),
          if (clientMode) ...[
            const SizedBox(width: 4),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                fullscreen
                    ? Icons.fullscreen_exit_rounded
                    : Icons.fullscreen_rounded,
                color: Colors.white,
              ),
              onPressed: onFullscreen,
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.description_outlined,
              size: 56,
              color: AppTheme.getTextSecondary(context),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.getTextSecondary(context),
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.navy,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
