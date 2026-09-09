import 'package:flutter/material.dart';

/// Coordinates Live Test Auto Run so My Tasks can open the real action sheets
/// on screen, pause so they are visible, then auto-submit.
class MobileLiveTestAutoPlay extends ChangeNotifier {
  MobileLiveTestAutoPlay._();

  static final MobileLiveTestAutoPlay instance = MobileLiveTestAutoPlay._();

  bool running = false;
  bool actionInFlight = false;
  String status = '';
  int _generation = 0;
  final Set<String> _claimed = <String>{};

  Duration openDelay = const Duration(milliseconds: 200);
  Duration previewDelay = const Duration(milliseconds: 350);

  bool get isActive => running;

  void start() {
    running = true;
    actionInFlight = false;
    _claimed.clear();
    _generation++;
    status = 'Auto run: opening the next action…';
    notifyListeners();
    _scheduleIdleFinish(_generation);
  }

  void stop() {
    running = false;
    actionInFlight = false;
    status = 'Stopped.';
    _generation++;
    notifyListeners();
  }

  bool tryClaim(String key) {
    if (!running || actionInFlight) return false;
    if (key.isEmpty || _claimed.contains(key)) return false;
    _claimed.add(key);
    actionInFlight = true;
    status = 'Auto run: opening action…';
    notifyListeners();
    return true;
  }

  void finishAction() {
    actionInFlight = false;
    if (running) {
      status = 'Auto run: opening the next action…';
      _scheduleIdleFinish(_generation);
    }
    notifyListeners();
  }

  void _scheduleIdleFinish(int generation) {
    Future<void>.delayed(const Duration(seconds: 8), () {
      if (generation != _generation || !running || actionInFlight) return;
      running = false;
      status = 'Auto run finished.';
      notifyListeners();
    });
  }
}

class LiveTestAutoPlayHook extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onPlay;

  const LiveTestAutoPlayHook({
    super.key,
    required this.child,
    required this.onPlay,
  });

  @override
  State<LiveTestAutoPlayHook> createState() => _LiveTestAutoPlayHookState();
}

class _LiveTestAutoPlayHookState extends State<LiveTestAutoPlayHook> {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_started || !mounted) return;
    final play = MobileLiveTestAutoPlay.instance;
    if (!play.running) return;
    _started = true;
    await Future<void>.delayed(play.previewDelay);
    if (!mounted || !play.running) return;
    await widget.onPlay();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
