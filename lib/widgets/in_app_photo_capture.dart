import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// In-app photo capture. Keeps the Flutter engine/activity alive (unlike the
/// external camera intent used by image_picker, which lets Android kill the
/// app and cold-start it on the splash screen).
/// Pops with an [XFile] or null. Pops with the string 'fallback' if the camera
/// can't be opened so the caller can use image_picker instead.
class InAppPhotoCapturePage extends StatefulWidget {
  const InAppPhotoCapturePage({super.key});
  @override
  State<InAppPhotoCapturePage> createState() => _InAppPhotoCapturePageState();
}

class _InAppPhotoCapturePageState extends State<InAppPhotoCapturePage>
    with WidgetsBindingObserver {
  CameraController? _controller;
  bool _busy = false;
  List<CameraDescription> _cameras = const [];
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) throw Exception('no camera');
      final rear = _cameras.indexWhere(
          (c) => c.lensDirection == CameraLensDirection.back);
      _index = rear < 0 ? 0 : rear;
      await _open();
    } catch (_) {
      if (mounted) Navigator.of(context).pop('fallback');
    }
  }

  Future<void> _open() async {
    final old = _controller;
    _controller = null;
    if (mounted) setState(() {});
    await old?.dispose();
    final c = CameraController(_cameras[_index], ResolutionPreset.high,
        enableAudio: false);
    await c.initialize();
    if (!mounted) {
      await c.dispose();
      return;
    }
    setState(() => _controller = c);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller = null;
      c.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _open().catchError((_) {});
    }
  }

  Future<void> _capture() async {
    final c = _controller;
    if (c == null || _busy || !c.value.isInitialized) return;
    setState(() => _busy = true);
    try {
      final file = await c.takePicture();
      if (mounted) Navigator.of(context).pop(file);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(children: [
          Positioned.fill(
            child: c != null && c.value.isInitialized
                ? Center(child: CameraPreview(c))
                : const Center(
                    child: CircularProgressIndicator(color: Colors.white)),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                const SizedBox(width: 48),
                GestureDetector(
                  onTap: _capture,
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 5),
                      color: _busy ? Colors.grey : Colors.white24,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.cameraswitch,
                      color: Colors.white, size: 32),
                  onPressed: _cameras.length < 2 || _busy
                      ? null
                      : () {
                          _index = (_index + 1) % _cameras.length;
                          _open().catchError((_) {});
                        },
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
