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
///
/// Only paints the page shell + canvas / 3D hosts — never side drawers or
/// menus (painting those made AR menu labels unreadable).
const String kIsometricViewerScript = r'''
(function () {
  var css = '#3A3A3A';
  var hex = 0x3A3A3A;
  function classNameOf(el) {
    if (!el || !el.className) return '';
    if (typeof el.className === 'string') return el.className.toLowerCase();
    if (el.className.baseVal) return String(el.className.baseVal).toLowerCase();
    return '';
  }
  function isUiChrome(el) {
    if (!el || el === document.body || el === document.documentElement) return false;
    var tag = (el.tagName || '').toLowerCase();
    if (tag === 'aside' || tag === 'nav' || tag === 'button' || tag === 'a' ||
        tag === 'li' || tag === 'ul' || tag === 'ol' || tag === 'label' ||
        tag === 'input' || tag === 'select' || tag === 'textarea') {
      return true;
    }
    var id = (el.id || '').toLowerCase();
    var role = '';
    try { role = (el.getAttribute && (el.getAttribute('role') || '') || '').toLowerCase(); } catch (e) {}
    var hay = classNameOf(el) + ' ' + id + ' ' + role;
    return /drawer|sidebar|side-bar|sidepanel|side-panel|menu|toolbar|overlay|modal|dialog|panel|settings|controls|hud|ui-|vrs[-_]?drawer|vrs[-_]?menu|vrs[-_]?sidebar/.test(hay);
  }
  function paintElement(el) {
    if (!el || !el.style || isUiChrome(el)) return;
    el.style.background = css;
    el.style.backgroundColor = css;
  }
  paintElement(document.documentElement);
  paintElement(document.body);
  var nodes = document.querySelectorAll('canvas, .viewer, .scene, model-viewer');
  for (var i = 0; i < nodes.length; i++) {
    paintElement(nodes[i]);
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

/// Makes AR / VR side-drawer and menu labels high-contrast inside the viewer.
const String kIsometricDrawerContrastScript = r'''
(function () {
  var STYLE_ID = 'bah-isometric-drawer-contrast';
  var TEXT = '#F8FAFC';
  var MUTED = '#E2E8F0';
  var PANEL = '#1F2937';
  function ensureStyle() {
    var s = document.getElementById(STYLE_ID);
    if (!s) {
      s = document.createElement('style');
      s.id = STYLE_ID;
      (document.head || document.documentElement).appendChild(s);
    }
    s.textContent = [
      'aside, nav,',
      '[class*="drawer"], [class*="Drawer"],',
      '[class*="sidebar"], [class*="Sidebar"],',
      '[class*="side-bar"], [class*="sidepanel"], [class*="side-panel"],',
      '[class*="menu-panel"], [class*="MenuPanel"],',
      '[class*="vrs-drawer"], [class*="vrsDrawer"], [class*="vrs_menu"],',
      '[class*="vrs-menu"], [class*="vrsMenu"], [class*="vrs-sidebar"],',
      '[id*="drawer"], [id*="sidebar"], [id*="side-bar"],',
      '[id*="vrs-drawer"], [id*="vrs-menu"],',
      '[role="menu"], [role="navigation"], [role="dialog"], [role="complementary"] {',
      '  background-color: ' + PANEL + ' !important;',
      '  background: ' + PANEL + ' !important;',
      '  color: ' + TEXT + ' !important;',
      '  -webkit-text-fill-color: ' + TEXT + ' !important;',
      '  text-shadow: none !important;',
      '  opacity: 1 !important;',
      '}',
      'aside *, nav *,',
      '[class*="drawer"] *, [class*="Drawer"] *,',
      '[class*="sidebar"] *, [class*="Sidebar"] *,',
      '[class*="side-bar"] *, [class*="sidepanel"] *, [class*="side-panel"] *,',
      '[class*="menu-panel"] *, [class*="MenuPanel"] *,',
      '[class*="vrs-drawer"] *, [class*="vrsDrawer"] *, [class*="vrs-menu"] *,',
      '[class*="vrsMenu"] *, [class*="vrs-sidebar"] *,',
      '[id*="drawer"] *, [id*="sidebar"] *, [id*="side-bar"] *,',
      '[id*="vrs-drawer"] *, [id*="vrs-menu"] *,',
      '[role="menu"] *, [role="navigation"] *, [role="dialog"] *, [role="complementary"] * {',
      '  color: ' + TEXT + ' !important;',
      '  -webkit-text-fill-color: ' + TEXT + ' !important;',
      '  fill: ' + TEXT + ' !important;',
      '  opacity: 1 !important;',
      '}',
      'aside span, nav span,',
      '[class*="drawer"] span, [class*="sidebar"] span,',
      '[class*="drawer"] label, [class*="sidebar"] label,',
      '[class*="drawer"] p, [class*="sidebar"] p,',
      '[class*="drawer"] a, [class*="sidebar"] a,',
      '[class*="drawer"] button, [class*="sidebar"] button,',
      '[role="menu"] span, [role="menuitem"], [role="menuitem"] * {',
      '  color: ' + TEXT + ' !important;',
      '  -webkit-text-fill-color: ' + TEXT + ' !important;',
      '  font-weight: 600 !important;',
      '}',
      'aside small, nav small, [class*="drawer"] small, [class*="sidebar"] small,',
      '[class*="drawer"] .subtitle, [class*="sidebar"] .muted {',
      '  color: ' + MUTED + ' !important;',
      '  -webkit-text-fill-color: ' + MUTED + ' !important;',
      '}'
    ].join("\n");
  }
  function classNameOf(el) {
    if (!el || !el.className) return '';
    if (typeof el.className === 'string') return el.className;
    if (el.className.baseVal) return String(el.className.baseVal);
    return '';
  }
  function looksLikeDrawer(el) {
    if (!el || !el.tagName) return false;
    var tag = el.tagName.toLowerCase();
    if (tag === 'aside' || tag === 'nav') return true;
    var role = '';
    try { role = (el.getAttribute && (el.getAttribute('role') || '') || '').toLowerCase(); } catch (e) {}
    if (role === 'menu' || role === 'navigation' || role === 'dialog' || role === 'complementary') {
      return true;
    }
    var hay = (classNameOf(el) + ' ' + (el.id || '')).toLowerCase();
    return /drawer|sidebar|side-bar|sidepanel|side-panel|menu-panel|main-menu|ar-menu|vr-menu|vrs[-_]?drawer|vrs[-_]?menu|vrs[-_]?sidebar/.test(hay);
  }
  function paintDrawer(el) {
    if (!el || !el.style) return;
    el.style.setProperty('background-color', PANEL, 'important');
    el.style.setProperty('background', PANEL, 'important');
    el.style.setProperty('color', TEXT, 'important');
    el.style.setProperty('-webkit-text-fill-color', TEXT, 'important');
    el.style.setProperty('opacity', '1', 'important');
    var nodes = el.querySelectorAll('a, button, span, p, label, li, div, h1, h2, h3, h4, h5, h6, small, svg, path');
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i];
      if (!n.style) continue;
      n.style.setProperty('color', TEXT, 'important');
      n.style.setProperty('-webkit-text-fill-color', TEXT, 'important');
      n.style.setProperty('opacity', '1', 'important');
      if (n.tagName && (n.tagName.toLowerCase() === 'svg' || n.tagName.toLowerCase() === 'path')) {
        n.style.setProperty('fill', TEXT, 'important');
      }
    }
  }
  function walk(root) {
    if (!root) return;
    if (root.querySelectorAll) {
      var all = root.querySelectorAll('*');
      for (var i = 0; i < all.length; i++) {
        if (looksLikeDrawer(all[i])) paintDrawer(all[i]);
        if (all[i].shadowRoot) walk(all[i].shadowRoot);
      }
    }
    if (root.shadowRoot) walk(root.shadowRoot);
  }
  function sweep() {
    try {
      ensureStyle();
      walk(document);
    } catch (e) {}
  }
  sweep();
  setTimeout(sweep, 400);
  setTimeout(sweep, 1200);
  setTimeout(sweep, 2400);
})();
''';

/// Hides only the in-viewer "View in AR" button. Does not touch the model.
const String kHideInViewerArButtonScript = r'''
(function () {
  function ownLabel(el) {
    var aria = '';
    if (el.getAttribute) {
      aria = (el.getAttribute('aria-label') || '') + ' ' + (el.getAttribute('title') || '');
    }
    var text = '';
    var nodes = el.childNodes || [];
    for (var i = 0; i < nodes.length; i++) {
      if (nodes[i].nodeType === 3) text += nodes[i].textContent || '';
    }
    return (aria + ' ' + text).toLowerCase();
  }
  function classNameOf(el) {
    if (!el.className) return '';
    if (typeof el.className === 'string') return el.className.toLowerCase();
    if (el.className.baseVal) return String(el.className.baseVal).toLowerCase();
    return '';
  }
  function hide(root) {
    if (!root || !root.querySelectorAll) return;
    var nodes = root.querySelectorAll('button, a, [role="button"]');
    for (var i = 0; i < nodes.length; i++) {
      var el = nodes[i];
      var slot = el.getAttribute ? (el.getAttribute('slot') || '') : '';
      var cls = classNameOf(el);
      var label = ownLabel(el);
      if (slot === 'ar-button' ||
          cls === 'ar-button' ||
          cls.indexOf('default-ar-button') !== -1 ||
          label.indexOf('view in ar') !== -1 ||
          label.indexOf('view in your space') !== -1) {
        el.style.setProperty('display', 'none', 'important');
      }
      if (el.shadowRoot) hide(el.shadowRoot);
    }
    var viewers = root.querySelectorAll('model-viewer');
    for (var j = 0; j < viewers.length; j++) {
      if (viewers[j].shadowRoot) hide(viewers[j].shadowRoot);
    }
  }
  function sweep() { try { hide(document); } catch (e) {} }
  sweep();
  setTimeout(sweep, 600);
  setTimeout(sweep, 1600);
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
    late final WebViewController controller;
    controller = WebViewController()
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
              await controller.runJavaScript(kIsometricViewerScript);
              await controller.runJavaScript(kIsometricDrawerContrastScript);
              await controller.runJavaScript(kHideInViewerArButtonScript);
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
          icon: Icon(Icons.arrow_back_rounded, color: AppTheme.darkTextPrimary),
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
              Text(
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
