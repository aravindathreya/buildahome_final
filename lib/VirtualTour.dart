import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'app_theme.dart';
import 'services/isometric_view_service.dart';
import 'services/session_manager.dart';

/// Dark grey behind the server isometric page and its WebView.
const Color _isometricBackground = Color(0xFF3A3A3A);

/// The isometric page is hosted on the server. Force its page and WebGL
/// clear color to dark grey after it loads.
const String _isometricBackgroundScript = r'''
(function () {
  var css = '#3A3A3A';
  var hex = 0x3A3A3A;
  function paintElement(el) {
    if (!el || !el.style) return;
    el.style.background = css;
    el.style.backgroundColor = css;
  }
  paintElement(document.documentElement);
  paintElement(document.body);
  var nodes = document.querySelectorAll('body, #app, #root, canvas, .viewer, .scene');
  for (var i = 0; i < nodes.length; i++) {
    paintElement(nodes[i]);
    if (nodes[i].parentElement) paintElement(nodes[i].parentElement);
  }
  var THREE = window.THREE;
  function paintObject(obj) {
    if (!obj || typeof obj !== 'object') return;
    try {
      if (obj.isScene) {
        if (obj.background && obj.background.isColor && obj.background.set) {
          obj.background.set(hex);
        } else if (THREE && THREE.Color) {
          obj.background = new THREE.Color(hex);
        }
      }
      if (typeof obj.setClearColor === 'function') obj.setClearColor(hex, 1);
    } catch (e) {}
  }
  var keys = Object.keys(window);
  for (var k = 0; k < keys.length; k++) {
    try { paintObject(window[keys[k]]); } catch (e) {}
  }
})();
''';

/// Full-screen isometric view. The page URL comes from the web API.
class VirtualTourScreen extends StatefulWidget {
  final String? title;

  const VirtualTourScreen({
    super.key,
    this.title,
  });

  @override
  State<VirtualTourScreen> createState() => _VirtualTourScreenState();
}

class _VirtualTourScreenState extends State<VirtualTourScreen> {
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
    } catch (e) {
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
      ..setBackgroundColor(_isometricBackground)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _pageLoading = true;
              _error = null;
            });
          },
          onPageFinished: (_) async {
            try {
              await controller.runJavaScript(_isometricBackgroundScript);
            } catch (_) {}
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

  Future<void> _handleBack(bool didPop) async {
    if (didPop) return;
    final controller = _controller;
    if (controller != null && await controller.canGoBack()) {
      await controller.goBack();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final showLoader = _error == null && (_fetchingLink || _pageLoading);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        _handleBack(didPop);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: _isometricBackground,
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (_controller != null) WebViewWidget(controller: _controller!),
              if (_error != null) _ErrorView(message: _error!, onRetry: _loadLink),
              if (showLoader) const _LoadingView(),
              _BackButton(onPressed: () => _handleBack(false)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _BackButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.paddingOf(context).top + 8,
      left: 12,
      child: Material(
        color: AppTheme.darkBackgroundSecondary,
        elevation: 3,
        shadowColor: AppTheme.softShadow,
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: 'Back',
          onPressed: onPressed,
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.darkTextPrimary),
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: _isometricBackground,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3.5,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Opening 3D House Tour',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
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
    return ColoredBox(
      color: AppTheme.darkBackgroundPrimary,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 72, 28, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.view_in_ar_outlined,
                size: 48,
                color: AppTheme.accentBlue,
              ),
              const SizedBox(height: 16),
              const Text(
                '3D House Tour unavailable',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.darkTextPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.mutedGrey,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.navy,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
