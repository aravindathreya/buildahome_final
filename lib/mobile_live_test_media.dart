import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// Selected file for Mobile Live Test multipart uploads.
class MobileLiveTestSelectedFile {
  final String path;
  final String name;
  final double? videoDurationSeconds;

  const MobileLiveTestSelectedFile({
    required this.path,
    required this.name,
    this.videoDurationSeconds,
  });
}

class MobileLiveTestVideoRecordResult {
  final String path;
  final String name;
  final double durationSeconds;

  const MobileLiveTestVideoRecordResult({
    required this.path,
    required this.name,
    required this.durationSeconds,
  });
}

Future<MobileLiveTestSelectedFile?> recordMobileLiveTestVideo({
  required BuildContext context,
  int maxDurationSeconds = 60,
  int maxSizeMb = 50,
}) async {
  final result = await Navigator.of(context).push<MobileLiveTestVideoRecordResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => MobileLiveTestVideoRecorderPage(
        maxDurationSeconds: maxDurationSeconds,
      ),
    ),
  );
  if (result == null) return null;

  final file = File(result.path);
  if (!await file.exists()) return null;
  final fileSize = await file.length();
  final maxBytes = maxSizeMb * 1024 * 1024;
  if (fileSize > maxBytes) {
    throw MobileLiveTestMediaException(
      'Video must be $maxSizeMb MB or smaller.',
    );
  }

  return MobileLiveTestSelectedFile(
    path: result.path,
    name: result.name,
    videoDurationSeconds: result.durationSeconds,
  );
}

class MobileLiveTestMediaException implements Exception {
  final String message;
  MobileLiveTestMediaException(this.message);
}

class MobileLiveTestVideoRecorderPage extends StatefulWidget {
  final int maxDurationSeconds;

  const MobileLiveTestVideoRecorderPage({
    super.key,
    required this.maxDurationSeconds,
  });

  @override
  State<MobileLiveTestVideoRecorderPage> createState() =>
      _MobileLiveTestVideoRecorderPageState();
}

class _MobileLiveTestVideoRecorderPageState
    extends State<MobileLiveTestVideoRecorderPage> {
  CameraController? _controller;
  bool _initializing = true;
  String? _initError;
  bool _isRecording = false;
  int _elapsedSeconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No camera available on this device.');
      }
      final rear = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        rear,
        ResolutionPreset.high,
        enableAudio: true,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initError = e.toString().replaceFirst('Exception: ', '');
        _initializing = false;
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _startRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_isRecording) return;
    await controller.startVideoRecording();
    setState(() {
      _isRecording = true;
      _elapsedSeconds = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
      if (_elapsedSeconds >= widget.maxDurationSeconds) {
        unawaited(_stopRecording());
      }
    });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final controller = _controller;
    if (controller == null || !_isRecording) return;
    setState(() => _isRecording = false);
    try {
      final file = await controller.stopVideoRecording();
      final path = file.path;
      if (path.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
      final name = path.split(Platform.pathSeparator).last;
      Navigator.of(context).pop(
        MobileLiveTestVideoRecordResult(
          path: path,
          name: name.isNotEmpty ? name : 'video.mp4',
          durationSeconds: _elapsedSeconds.toDouble(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Record video'),
      ),
      body: _initializing
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _initError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _initError!,
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: _controller != null
                            ? CameraPreview(_controller!)
                            : const SizedBox.shrink(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _formatDuration(_elapsedSeconds),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(width: 24),
                          GestureDetector(
                            onTap: _isRecording
                                ? () => _stopRecording()
                                : () => _startRecording(),
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isRecording
                                    ? Colors.red
                                    : Colors.white,
                                border: Border.all(color: Colors.white, width: 3),
                              ),
                              child: Icon(
                                _isRecording ? Icons.stop : Icons.videocam,
                                color: _isRecording ? Colors.white : Colors.red,
                                size: 32,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
