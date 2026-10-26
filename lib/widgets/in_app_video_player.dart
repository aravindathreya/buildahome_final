import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/authenticated_document_fetcher.dart';
import '../services/document_file_share_io.dart';

/// Video extensions the in-app player tries. mp4 (H.264/AAC), webm, 3gp and
/// m4v play on nearly every phone; mov, mkv, avi, mpeg, wmv, flv and ts
/// depend on the phone's codecs (the player then offers Open with...).
const List<String> kInAppVideoExtensions = [
  '.mp4', '.mov', '.m4v', '.webm', '.3gp', '.3g2', '.mkv', '.avi',
  '.mpeg', '.mpg', '.wmv', '.flv', '.ts', '.mts', '.m2ts',
];

/// Audio extensions the in-app player tries.
const List<String> kInAppAudioExtensions = [
  '.mp3', '.m4a', '.aac', '.wav', '.ogg', '.oga', '.opus', '.amr', '.flac',
  '.wma',
];

/// True when a URL / name / mime type looks like a playable video.
bool looksLikeVideoFile({String url = '', String name = '', String contentType = ''}) {
  final mime = contentType.trim().toLowerCase();
  if (mime.startsWith('video/')) return true;
  if (mime.startsWith('audio/')) return false;
  final path = url.split('?').first.toLowerCase();
  final lowerName = name.toLowerCase();
  return kInAppVideoExtensions
      .any((e) => path.endsWith(e) || lowerName.endsWith(e));
}

/// True when a URL / name / mime type looks like a playable audio file.
bool looksLikeAudioFile({String url = '', String name = '', String contentType = ''}) {
  final mime = contentType.trim().toLowerCase();
  if (mime.startsWith('audio/')) return true;
  if (mime.startsWith('video/')) return false;
  final path = url.split('?').first.toLowerCase();
  final lowerName = name.toLowerCase();
  return kInAppAudioExtensions
      .any((e) => path.endsWith(e) || lowerName.endsWith(e));
}

/// Plays an audio file in the app (play / pause / seek / duration).
Future<void> openInAppAudio(
  BuildContext context, {
  required String url,
  String title = 'Audio',
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => InAppVideoPlayerScreen(url: url, title: title, audio: true),
    ),
  );
}

Future<void> openInAppVideo(
  BuildContext context, {
  required String url,
  String title = 'Video',
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => InAppVideoPlayerScreen(url: url, title: title),
    ),
  );
}

/// Plays a video inside the app using the platform web view's native
/// <video> player (play / pause / seek). Streams with the app's api token;
/// if streaming fails, downloads to a temp file and plays that.
class InAppVideoPlayerScreen extends StatefulWidget {
  const InAppVideoPlayerScreen({
    super.key,
    required this.url,
    this.title = 'Video',
    this.audio = false,
  });

  final String url;
  final String title;

  /// Uses an <audio> element instead of <video>.
  final bool audio;

  @override
  State<InAppVideoPlayerScreen> createState() => _InAppVideoPlayerScreenState();
}

class _InAppVideoPlayerScreenState extends State<InAppVideoPlayerScreen> {
  WebViewController? _controller;
  bool _loading = true;
  String? _error;
  bool _triedFile = false;
  File? _tempFile;
  bool _sharing = false;

  String get _failMessage => widget.audio
      ? 'This audio could not be played here. Its format may not be '
          'supported on this phone. Use Open with… to play it in another app.'
      : 'This video could not be played here. Its format or codec may not be '
          'supported on this phone. Use Open with… to play it in another app.';

  String get _fileName {
    final path = widget.url.split('?').first;
    final slash = path.lastIndexOf('/');
    var name = slash >= 0 ? path.substring(slash + 1) : path;
    try {
      name = Uri.decodeComponent(name);
    } catch (_) {}
    if (name.trim().isEmpty) name = widget.title;
    return name.trim().isEmpty ? (widget.audio ? 'audio' : 'video') : name;
  }

  Future<void> _openWith() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final client = http.Client();
    try {
      List<int>? bytes;
      final f = _tempFile;
      if (f != null && await f.exists()) {
        bytes = await f.readAsBytes();
      } else {
        final prepared =
            await AuthenticatedDocumentFetcher.instance.prepareRequest(widget.url);
        final response = await client
            .get(prepared.uri, headers: prepared.headers)
            .timeout(const Duration(minutes: 2));
        final type = (response.headers['content-type'] ?? '').toLowerCase();
        if (response.statusCode >= 200 &&
            response.statusCode < 300 &&
            !type.contains('text/html') &&
            !type.contains('json')) {
          bytes = response.bodyBytes;
        }
      }
      if (bytes == null || bytes.isEmpty) throw Exception('no bytes');
      await shareDocumentBytes(
        bytes: Uint8List.fromList(bytes),
        fileName: _fileName,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not download this file')),
        );
      }
    } finally {
      client.close();
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _startStream();
  }

  @override
  void dispose() {
    final f = _tempFile;
    if (f != null) {
      f.parent.delete(recursive: true).catchError((_) => f.parent);
    }
    super.dispose();
  }

  WebViewController _newController() {
    final c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('VideoStatus', onMessageReceived: (msg) {
        if (!mounted) return;
        if (msg.message == 'ready') {
          setState(() => _loading = false);
        } else if (msg.message == 'error' || msg.message == 'novideo') {
          _onStreamError();
        }
      });
    return c;
  }

  String _html(String src) {
    final safe = const HtmlEscape(HtmlEscapeMode.attribute).convert(src);
    if (widget.audio) {
      final label = const HtmlEscape().convert(widget.title);
      return '<!DOCTYPE html><html><head>'
          '<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">'
          '<style>html,body{margin:0;height:100%;background:#000;color:#ddd;'
          'font-family:sans-serif;}body{display:flex;flex-direction:column;'
          'align-items:center;justify-content:center;}'
          '.n{margin:0 16px 20px;text-align:center;word-break:break-word;font-size:15px;}'
          'audio{width:92%;}</style>'
          '</head><body><div class="n">&#9835; $label</div>'
          '<audio id="v" src="$safe" controls preload="metadata"></audio>'
          '<script>var v=document.getElementById("v");'
          'v.addEventListener("loadedmetadata",function(){VideoStatus.postMessage("ready");});'
          'v.addEventListener("error",function(){VideoStatus.postMessage("error");});'
          '</script></body></html>';
    }
    return '<!DOCTYPE html><html><head>'
        '<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">'
        '<style>html,body{margin:0;height:100%;background:#000;}'
        'video{width:100%;height:100%;object-fit:contain;background:#000;}</style>'
        '</head><body>'
        '<video id="v" src="$safe" controls playsinline preload="metadata"></video>'
        '<script>var v=document.getElementById("v");'
        'v.addEventListener("loadedmetadata",function(){'
        'if(!v.videoWidth&&!v.videoHeight){VideoStatus.postMessage("novideo");}'
        'else{VideoStatus.postMessage("ready");}});'
        'v.addEventListener("error",function(){VideoStatus.postMessage("error");});'
        '</script></body></html>';
  }

  Future<void> _startStream() async {
    try {
      final prepared =
          await AuthenticatedDocumentFetcher.instance.prepareRequest(widget.url);
      final c = _newController();
      await c.loadHtmlString(
        _html(prepared.uri.toString()),
        baseUrl: AuthenticatedDocumentFetcher.baseUrl,
      );
      if (!mounted) return;
      setState(() => _controller = c);
      Future.delayed(const Duration(seconds: 20), () {
        if (mounted && _loading && !_triedFile) _onStreamError();
      });
    } catch (_) {
      _onStreamError();
    }
  }

  void _onStreamError() {
    if (_triedFile) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _failMessage;
        });
      }
      return;
    }
    _triedFile = true;
    _playFromTempFile();
  }

  Future<void> _playFromTempFile() async {
    if (mounted) setState(() => _loading = true);
    final client = http.Client();
    try {
      final prepared =
          await AuthenticatedDocumentFetcher.instance.prepareRequest(widget.url);
      final request = http.Request('GET', prepared.uri)
        ..headers.addAll(prepared.headers);
      final response =
          await client.send(request).timeout(const Duration(seconds: 30));
      final type = (response.headers['content-type'] ?? '').toLowerCase();
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          type.contains('text/html') ||
          type.contains('json')) {
        throw Exception('bad response');
      }
      final base = await getTemporaryDirectory();
      final dir = await Directory(
              '${base.path}/chat_video_${DateTime.now().millisecondsSinceEpoch}')
          .create(recursive: true);
      var ext = widget.audio ? '.mp3' : '.mp4';
      final path = widget.url.split('?').first.toLowerCase();
      final lowerTitle = widget.title.toLowerCase();
      for (final e in widget.audio ? kInAppAudioExtensions : kInAppVideoExtensions) {
        if (path.endsWith(e) || lowerTitle.endsWith(e)) ext = e;
      }
      final file = File('${dir.path}/video$ext');
      final sink = file.openWrite();
      await response.stream.pipe(sink);
      _tempFile = file;
      final page = File('${dir.path}/player.html');
      await page.writeAsString(_html('video$ext'));
      final c = _newController();
      await c.loadFile(page.path);
      if (!mounted) return;
      setState(() {
        _controller = c;
        _error = null;
      });
      Future.delayed(const Duration(seconds: 20), () {
        if (mounted && _loading) {
          setState(() {
            _loading = false;
            _error = _failMessage;
          });
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _failMessage;
        });
      }
    } finally {
      client.close();
    }
  }

  void _retry() {
    setState(() {
      _error = null;
      _loading = true;
      _triedFile = false;
      _controller = null;
    });
    _startStream();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
      ),
      body: Stack(
        children: [
          if (controller != null && _error == null)
            Positioned.fill(child: WebViewWidget(controller: controller)),
          if (_loading && _error == null)
            const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            ),
          if (_error != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                        widget.audio
                            ? Icons.music_off_rounded
                            : Icons.videocam_off_rounded,
                        color: Colors.white70,
                        size: 48),
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        OutlinedButton(
                          onPressed: _retry,
                          child: const Text('Retry'),
                        ),
                        ElevatedButton.icon(
                          onPressed: _sharing ? null : _openWith,
                          icon: _sharing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.open_in_new_rounded),
                          label: const Text('Download / Open with…'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}