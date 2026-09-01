import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import 'package:photo_view/photo_view.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../client_portal/client_portal_document_ui.dart';
import '../models/workflow_document.dart';
import '../services/authenticated_document_fetcher.dart';
import '../widgets/skeleton_loader.dart';

/// Opens a workflow document with authenticated byte fetch + native viewer.
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
    setState(() {
      _loading = true;
      _errorMessage = null;
      _result = null;
    });

    _pdfController?.dispose();
    _pdfController = null;

    final fetch = await AuthenticatedDocumentFetcher.instance.fetch(
      url: widget.document.url!,
      documentId: widget.document.id,
      contentTypeHint: widget.document.contentType,
      isPdfHint: widget.document.isPdf,
      isImageHint: widget.document.isImage,
    );

    if (!mounted) return;

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
      try {
        final doc = await PdfDocument.openData(fetch.bytes!);
        final controller = PdfControllerPinch(document: Future.value(doc));
        if (!mounted) {
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

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(widget.document.url ?? '');
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.document.displayTitle;
    final showClientFooter =
        widget.clientMode && !_loading && _errorMessage == null;

    return Scaffold(
      backgroundColor: _result?.kind == DocumentPayloadKind.image
          ? Colors.black
          : const Color(0xFFF7F8FB),
      appBar: _fullscreen
          ? null
          : AppBar(
              backgroundColor: widget.clientMode && _isImage
                  ? Colors.black
                  : AppTheme.getBackgroundSecondary(context),
              foregroundColor: widget.clientMode && _isImage
                  ? Colors.white
                  : AppTheme.navy,
              elevation: 0,
              title: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: widget.clientMode && _isImage
                      ? Colors.white
                      : AppTheme.navy,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              actions: [
                if (!_loading && _pdfController != null)
                  IconButton(
                    icon: const Icon(Icons.fullscreen_rounded),
                    onPressed: _toggleFullscreen,
                    tooltip: 'Fullscreen',
                  ),
                if (!widget.clientMode && !_loading && _errorMessage != null)
                  IconButton(
                    icon: const Icon(Icons.open_in_new_rounded),
                    onPressed: _openExternal,
                    tooltip: 'Open externally',
                  ),
              ],
            ),
      body: Column(
        children: [
          Expanded(child: _buildBody()),
          if (showClientFooter)
            SafeArea(
              top: false,
              child: ClientPortalViewerDocCard(document: widget.document),
            ),
        ],
      ),
    );
  }

  bool get _isImage => _result?.kind == DocumentPayloadKind.image;

  Widget _buildBody() {
    if (_loading) {
      return const SkeletonListLoader(showSummary: false, cardCount: 3);
    }

    if (_errorMessage != null) {
      return _ErrorView(
        message: _errorMessage!,
        onRetry: _loadDocument,
        showExternal: !widget.clientMode,
        onExternal: _openExternal,
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
                  showExternal: !widget.clientMode,
                  onExternal: _openExternal,
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
      showExternal: !widget.clientMode,
      onExternal: _openExternal,
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
  final bool showExternal;
  final VoidCallback? onExternal;

  const _ErrorView({
    required this.message,
    required this.onRetry,
    this.showExternal = false,
    this.onExternal,
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
            if (showExternal && onExternal != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onExternal,
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Open externally'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
