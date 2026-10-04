import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_theme.dart';
import '../services/isometric_view_service.dart';
import '../services/session_manager.dart';

/// Compact isometric WebView for the project homepage hero.
class VirtualTourEmbed extends StatefulWidget {
  final double height;
  final VoidCallback? onExpand;

  const VirtualTourEmbed({
    super.key,
    this.height = 200,
    this.onExpand,
  });

  @override
  State<VirtualTourEmbed> createState() => _VirtualTourEmbedState();
}

class _VirtualTourEmbedState extends State<VirtualTourEmbed> {
  WebViewController? _controller;
  bool _fetchingLink = true;
  bool _pageLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLink();
  }

  Future<void> _loadLink() async {
    setState(() {
      _fetchingLink = true;
      _pageLoading = false;
      _error = null;
      _controller = null;
    });

    try {
      final uri = await IsometricViewService.instance.fetchPageUri();
      if (!mounted) return;
      _openPage(uri);
    } on SessionInvalidatedException {
      return;
    } on IsometricViewException catch (e) {
      if (!mounted) return;
      setState(() {
        _fetchingLink = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _fetchingLink = false;
        _error = 'Could not open the 3D House Tour.';
      });
    }
  }

  void _openPage(Uri uri) {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppTheme.darkBackgroundPrimary)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _pageLoading = true;
              _error = null;
            });
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() => _pageLoading = false);
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            if (error.isForMainFrame == false) return;
            setState(() {
              _pageLoading = false;
              _error = error.description.isEmpty
                  ? 'Could not open the 3D House Tour.'
                  : error.description;
            });
          },
        ),
      )
      ..loadRequest(uri);

    setState(() {
      _controller = controller;
      _fetchingLink = false;
      _pageLoading = true;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showLoader = _error == null && (_fetchingLink || _pageLoading);

    return SizedBox(
      height: widget.height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppTheme.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: AppTheme.darkBackgroundPrimary),
              if (_controller != null)
                WebViewWidget(
                  controller: _controller!,
                  gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                    Factory<OneSequenceGestureRecognizer>(
                      () => EagerGestureRecognizer(),
                    ),
                  },
                ),
              if (_error != null)
                _EmbedError(message: _error!, onRetry: _loadLink),
              if (showLoader) const _EmbedLoading(),
              Positioned(
                left: 12,
                top: 12,
                child: _Chip(
                  icon: Icons.view_in_ar_rounded,
                  label: '3D House Tour',
                ),
              ),
              if (widget.onExpand != null)
                Positioned(
                  right: 12,
                  top: 12,
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: 'Open',
                      onPressed: widget.onExpand,
                      icon: const Icon(
                        Icons.open_in_new_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _Chip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmbedLoading extends StatelessWidget {
  const _EmbedLoading();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTheme.darkBackgroundPrimary.withValues(alpha: 0.92),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: AppTheme.accentBlue,
              ),
            ),
            SizedBox(height: 10),
            Text(
              'Loading 3D view',
              style: TextStyle(
                color: AppTheme.darkTextPrimary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmbedError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _EmbedError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTheme.darkBackgroundPrimary,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.view_in_ar_outlined,
                size: 28,
                color: AppTheme.accentBlue,
              ),
              const SizedBox(height: 8),
              Text(
                '3D view unavailable',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.darkTextPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                message,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.mutedGrey,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
