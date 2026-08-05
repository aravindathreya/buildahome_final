import 'dart:async';

import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'widgets/themed_scaffold.dart';

/// Interactive 3D walkthrough of the home model (GLB).
class VirtualTourScreen extends StatefulWidget {
  final String? modelSrc;
  final String? title;

  const VirtualTourScreen({
    super.key,
    this.modelSrc,
    this.title,
  });

  @override
  State<VirtualTourScreen> createState() => _VirtualTourScreenState();
}

class _TourViewpoint {
  final String id;
  final String label;
  final IconData icon;
  final String cameraOrbit;
  final String cameraTarget;

  const _TourViewpoint({
    required this.id,
    required this.label,
    required this.icon,
    required this.cameraOrbit,
    required this.cameraTarget,
  });
}

class _VirtualTourScreenState extends State<VirtualTourScreen> {
  // Mobile-optimized bedroom GLB (no Draco — loads offline in WebView).
  static const String _defaultModel = 'assets/models/nihira_bedroom.glb';
  static const String _centerTarget = '0m 0.15m 0m';

  String _projectName = 'Your Home';
  bool _autoRotate = true;
  bool _showTips = true;
  bool _isLoading = true;
  String _activeViewpointId = 'overview';
  late String _cameraOrbit;
  late String _cameraTarget;
  int _viewerEpoch = 0;
  Timer? _loadTimeout;

  static const List<_TourViewpoint> _viewpoints = [
    _TourViewpoint(
      id: 'overview',
      label: 'Overview',
      icon: Icons.home_work_outlined,
      cameraOrbit: '35deg 65deg 3.2m',
      cameraTarget: _centerTarget,
    ),
    _TourViewpoint(
      id: 'front',
      label: 'Front',
      icon: Icons.door_front_door_outlined,
      cameraOrbit: '0deg 75deg 2.8m',
      cameraTarget: _centerTarget,
    ),
    _TourViewpoint(
      id: 'living',
      label: 'Living',
      icon: Icons.weekend_outlined,
      cameraOrbit: '55deg 78deg 2.4m',
      cameraTarget: '0.1m 0.2m -0.1m',
    ),
    _TourViewpoint(
      id: 'bedroom',
      label: 'Bedroom',
      icon: Icons.bed_outlined,
      cameraOrbit: '210deg 72deg 2.2m',
      cameraTarget: '-0.1m 0.15m 0.1m',
    ),
    _TourViewpoint(
      id: 'side',
      label: 'Side',
      icon: Icons.view_sidebar_outlined,
      cameraOrbit: '95deg 70deg 2.9m',
      cameraTarget: _centerTarget,
    ),
    _TourViewpoint(
      id: 'aerial',
      label: 'Aerial',
      icon: Icons.flight_outlined,
      cameraOrbit: '25deg 35deg 4.0m',
      cameraTarget: '0m 0m 0m',
    ),
  ];

  @override
  void initState() {
    super.initState();
    final overview = _viewpoints.first;
    _cameraOrbit = overview.cameraOrbit;
    _cameraTarget = overview.cameraTarget;
    _loadProjectName();
    _armLoadTimeout();
  }

  @override
  void dispose() {
    _loadTimeout?.cancel();
    super.dispose();
  }

  void _armLoadTimeout() {
    _loadTimeout?.cancel();
    _loadTimeout = Timer(const Duration(seconds: 12), () {
      if (!mounted || !_isLoading) return;
      setState(() => _isLoading = false);
    });
  }

  Future<void> _loadProjectName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString('client_name') ??
        prefs.getString('project_name') ??
        prefs.getString('project_value');
    if (!mounted || name == null || name.trim().isEmpty) return;
    setState(() => _projectName = name.trim());
  }

  void _applyViewpoint(_TourViewpoint view) {
    setState(() {
      _activeViewpointId = view.id;
      _cameraOrbit = view.cameraOrbit;
      _cameraTarget = view.cameraTarget;
      _autoRotate = false;
      _isLoading = true;
      _viewerEpoch++;
    });
    _armLoadTimeout();
  }

  void _toggleAutoRotate() {
    setState(() {
      _autoRotate = !_autoRotate;
      _isLoading = true;
      _viewerEpoch++;
    });
    _armLoadTimeout();
  }

  void _resetCamera() {
    final overview = _viewpoints.first;
    setState(() {
      _activeViewpointId = overview.id;
      _cameraOrbit = overview.cameraOrbit;
      _cameraTarget = overview.cameraTarget;
      _autoRotate = true;
      _isLoading = true;
      _viewerEpoch++;
    });
    _armLoadTimeout();
  }

  String get _modelSrc => widget.modelSrc ?? _defaultModel;

  @override
  Widget build(BuildContext context) {
    return ThemedScaffold(
      title: widget.title ?? 'Virtual Tour',
      backgroundColor: const Color(0xFFF7F8FB),
      actions: [
        IconButton(
          tooltip: _autoRotate ? 'Stop rotation' : 'Auto rotate',
          onPressed: _toggleAutoRotate,
          icon: Icon(
            _autoRotate ? Icons.pause_circle_outline : Icons.rotate_right,
            color: _autoRotate ? AppTheme.accentBlue : AppTheme.navy,
          ),
        ),
        IconButton(
          tooltip: 'Reset view',
          onPressed: _resetCamera,
          icon: const Icon(Icons.center_focus_strong_outlined),
        ),
      ],
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildViewer(),
                if (_isLoading) _buildLoadingOverlay(),
                if (_showTips && !_isLoading) _buildTipsCard(),
              ],
            ),
          ),
          _buildViewpointBar(),
          _buildGestureHint(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppTheme.border),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFDBEAFE),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.view_in_ar_rounded,
              color: AppTheme.accentBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _projectName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.navy,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isLoading
                      ? 'Loading 3D model…'
                      : 'Explore your home in 3D',
                  style: const TextStyle(
                    color: AppTheme.mutedGrey,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewer() {
    return ColoredBox(
      color: const Color(0xFFE8EEF7),
      child: ModelViewer(
        key: ValueKey('virtual-tour-$_viewerEpoch'),
        backgroundColor: const Color(0xFFE8EEF7),
        src: _modelSrc,
        alt: '3D model of your home',
        ar: false,
        autoRotate: _autoRotate,
        autoRotateDelay: 0,
        cameraControls: true,
        disableZoom: false,
        cameraOrbit: _cameraOrbit,
        cameraTarget: _cameraTarget,
        fieldOfView: '45deg',
        exposure: 1.1,
        shadowIntensity: 0.4,
        environmentImage: 'neutral',
        loading: Loading.eager,
        reveal: Reveal.auto,
        interactionPrompt: InteractionPrompt.none,
        debugLogging: true,
        javascriptChannels: {
          JavascriptChannel(
            'VirtualTourBridge',
            onMessageReceived: (message) {
              debugPrint('VirtualTourBridge: ${message.message}');
              if (!mounted) return;
              final msg = message.message;
              if (msg == 'loaded' || msg.startsWith('visible')) {
                _loadTimeout?.cancel();
                setState(() => _isLoading = false);
              } else if (msg.startsWith('error:')) {
                _loadTimeout?.cancel();
                setState(() => _isLoading = false);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(msg),
                    backgroundColor: const Color(0xFFB91C1C),
                  ),
                );
              }
            },
          ),
        },
        relatedJs: '''
          (function () {
            const el = document.querySelector('model-viewer');
            if (!el) return;
            const send = (m) => {
              try { VirtualTourBridge.postMessage(m); } catch (e) {}
            };
            el.addEventListener('load', () => send('loaded'));
            el.addEventListener('error', (e) => {
              const detail = (e && e.detail) ? JSON.stringify(e.detail) : 'unknown';
              send('error:' + detail);
            });
            el.addEventListener('model-visibility', (e) => {
              if (e.detail && e.detail.visible) send('visible');
            });
            if (el.loaded) send('loaded');
          })();
        ''',
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: const Color(0xCCF7F8FB),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3.5,
                color: AppTheme.accentBlue,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Loading virtual tour',
              style: TextStyle(
                color: AppTheme.navy,
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipsCard() {
    return Positioned(
      left: 16,
      right: 16,
      top: 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.96),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.border),
            boxShadow: const [
              BoxShadow(
                color: AppTheme.softShadow,
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.touch_app_rounded,
                  color: AppTheme.accentBlue, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Drag to look around · Pinch to zoom · Use the stops below for guided views',
                  style: TextStyle(
                    color: AppTheme.navy,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: () => setState(() => _showTips = false),
                icon: const Icon(Icons.close_rounded, size: 18),
                color: AppTheme.mutedGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewpointBar() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: SizedBox(
        height: 86,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _viewpoints.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final view = _viewpoints[index];
            final selected = view.id == _activeViewpointId;
            return _ViewpointChip(
              viewpoint: view,
              selected: selected,
              onTap: () => _applyViewpoint(view),
            );
          },
        ),
      ),
    );
  }

  Widget _buildGestureHint() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: const Text(
        'Tip: rotate slowly around the home to inspect finishes and layout.',
        style: TextStyle(
          color: AppTheme.mutedGrey,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ViewpointChip extends StatelessWidget {
  final _TourViewpoint viewpoint;
  final bool selected;
  final VoidCallback onTap;

  const _ViewpointChip({
    required this.viewpoint,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? AppTheme.navy : const Color(0xFFF7F8FB);
    final fg = selected ? Colors.white : AppTheme.navy;
    final border = selected ? AppTheme.navy : AppTheme.border;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        width: 86,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(viewpoint.icon, color: fg, size: 22),
            const SizedBox(height: 8),
            Text(
              viewpoint.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: fg,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
