import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/mobile_live_test.dart';
import 'mobile_live_test_service.dart';

/// Owns Test Mode heartbeat + session polling while the dedicated screen
/// is visible. Stopping this does not cancel the backend workflow run.
class MobileLiveTestController extends ChangeNotifier {
  MobileLiveTestController({
    MobileLiveTestService? service,
    this.heartbeatInterval = const Duration(seconds: 20),
    this.pollInterval = const Duration(seconds: 5),
  }) : service = service ?? MobileLiveTestService.instance;

  final MobileLiveTestService service;
  final Duration heartbeatInterval;
  final Duration pollInterval;

  Timer? _heartbeatTimer;
  Timer? _pollTimer;
  int _generation = 0;
  bool _disposed = false;
  Future<void>? _refreshAfterCompleteInFlight;

  bool enabled = false;
  bool loading = false;
  bool syncing = false;
  String? error;
  MobileLiveTestSession session = MobileLiveTestSession.empty;
  MobileLiveTestDevice? heartbeatDevice;

  bool get isSyncActive => _heartbeatTimer != null || _pollTimer != null;

  bool get isWaiting => enabled && session.isWaitingForAssignment;

  List<MobileLiveTestTask> get visibleTasks => session.dedupedTasks;

  String get connectionLabel {
    final fromHeartbeat = heartbeatDevice?.connectionLabel;
    if (fromHeartbeat != null && fromHeartbeat.trim().isNotEmpty) {
      return fromHeartbeat;
    }
    return session.device?.connectionLabel ??
        (enabled ? 'Connected' : 'Offline');
  }

  Future<void> restoreAndRefresh() async {
    enabled = await service.isEnabled();
    if (!enabled) {
      session = MobileLiveTestSession.empty;
      heartbeatDevice = null;
      error = null;
      _notify();
      return;
    }
    await refresh();
  }

  Future<void> enable({String? displayName}) async {
    loading = true;
    error = null;
    _notify();
    try {
      await service.enable(displayName: displayName);
      enabled = true;
      await refresh();
      startSync();
    } on MobileLiveTestException catch (e) {
      error = e.message;
      enabled = await service.isEnabled();
      _notify();
      rethrow;
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
      enabled = await service.isEnabled();
      _notify();
      rethrow;
    } finally {
      loading = false;
      _notify();
    }
  }

  /// Local disconnect only. The assigned live-test run is left intact.
  Future<void> disable() async {
    stopSync();
    await service.disable();
    enabled = false;
    session = MobileLiveTestSession.empty;
    heartbeatDevice = null;
    error = null;
    _notify();
  }

  /// Remove a task from the local list immediately after completion.
  void dismissTask(int itemRunId) {
    if (itemRunId <= 0) return;
    final remaining = session.tasks
        .where((task) => task.itemRunId != itemRunId)
        .toList();
    if (remaining.length == session.tasks.length) return;
    session = MobileLiveTestSession(
      success: session.success,
      testMode: session.testMode,
      skipProjectGates: session.skipProjectGates,
      device: session.device,
      activeRun: session.activeRun,
      tasks: remaining,
      message: session.message,
    );
    _notify();
  }

  /// Optimistic list update after completion: remove finished task, surface new ones.
  void applyCompletionResult(
    MobileLiveTestCompletionResult result, {
    int? itemRunId,
  }) {
    if (!result.taskCompleted) return;
    final completedId =
        result.itemRunId > 0 ? result.itemRunId : (itemRunId ?? 0);
    if (completedId <= 0) return;
    dismissTask(completedId);
    service.invalidateOpenTaskCache(completedId);

    final incoming = result.newReadyTasks;
    if (incoming.isEmpty) {
      unawaited(refreshAfterTaskCompletion());
      return;
    }

    final existingIds = session.tasks
        .map((task) => task.itemRunId)
        .whereType<int>()
        .toSet();
    final merged = List<MobileLiveTestTask>.from(session.tasks);
    for (final task in incoming) {
      final id = task.itemRunId;
      if (id != null && id > 0 && !existingIds.contains(id)) {
        merged.add(task);
        existingIds.add(id);
      }
    }
    session = MobileLiveTestSession(
      success: session.success,
      testMode: session.testMode,
      skipProjectGates: session.skipProjectGates,
      device: session.device,
      activeRun: session.activeRun,
      tasks: merged,
      message: session.message,
    );
    _notify();
    unawaited(refreshAfterTaskCompletion());
  }

  /// Lightweight refresh after a task completes — no full-screen loading spinner.
  Future<void> refreshAfterTaskCompletion() {
    final inFlight = _refreshAfterCompleteInFlight;
    if (inFlight != null) return inFlight;
    final future = _refreshAfterTaskCompletionImpl();
    _refreshAfterCompleteInFlight = future;
    return future.whenComplete(() {
      if (identical(_refreshAfterCompleteInFlight, future)) {
        _refreshAfterCompleteInFlight = null;
      }
    });
  }

  Future<void> _refreshAfterTaskCompletionImpl() async {
    if (!await service.isEnabled()) {
      enabled = false;
      session = MobileLiveTestSession.empty;
      _notify();
      return;
    }
    final gen = _generation;
    error = null;
    try {
      final next = await service.fetchSession();
      if (gen != _generation) return;
      enabled = true;
      session = _mergeSessionTasks(session, next);
      if (next.device != null) heartbeatDevice = next.device;
    } on MobileLiveTestException catch (e) {
      if (gen != _generation) return;
      if (e.isDeviceAuthFailure) {
        enabled = false;
        session = MobileLiveTestSession.empty;
        heartbeatDevice = null;
      }
      error = e.message;
    } catch (e) {
      if (gen != _generation) return;
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (gen == _generation) {
        _notify();
      }
    }
  }

  Future<void> refresh() async {
    if (!await service.isEnabled()) {
      enabled = false;
      session = MobileLiveTestSession.empty;
      _notify();
      return;
    }
    final gen = _generation;
    loading = session.activeRun == null && session.tasks.isEmpty;
    error = null;
    _notify();
    try {
      final next = await service.fetchSession();
      if (gen != _generation) return;
      enabled = true;
      session = next;
      if (next.device != null) heartbeatDevice = next.device;
    } on MobileLiveTestException catch (e) {
      if (gen != _generation) return;
      if (e.isDeviceAuthFailure) {
        enabled = false;
        session = MobileLiveTestSession.empty;
        heartbeatDevice = null;
      }
      error = e.message;
    } catch (e) {
      if (gen != _generation) return;
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      if (gen == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  Future<void> sendHeartbeat() async {
    if (!enabled) return;
    final gen = _generation;
    try {
      final device = await service.heartbeat();
      if (gen != _generation) return;
      heartbeatDevice = device;
      _notify();
    } on MobileLiveTestException catch (e) {
      if (gen != _generation) return;
      if (e.isDeviceAuthFailure) {
        enabled = false;
        stopSync();
        session = MobileLiveTestSession.empty;
      }
      error = e.message;
      _notify();
    } catch (_) {}
  }

  void startSync() {
    stopSync(notify: false);
    if (!enabled) return;
    syncing = true;
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      unawaited(sendHeartbeat());
    });
    _pollTimer = Timer.periodic(pollInterval, (_) {
      unawaited(refresh());
    });
    unawaited(sendHeartbeat());
    _notify();
  }

  void stopSync({bool notify = true}) {
    _generation++;
    _heartbeatTimer?.cancel();
    _pollTimer?.cancel();
    _heartbeatTimer = null;
    _pollTimer = null;
    syncing = false;
    if (notify) _notify();
  }

  void _notify() {
    if (_disposed) return;
    super.notifyListeners();
  }

  /// Keep server fields fresh but prefer the local task ordering/count after dismiss.
  MobileLiveTestSession _mergeSessionTasks(
    MobileLiveTestSession local,
    MobileLiveTestSession remote,
  ) {
    final remoteById = <int, MobileLiveTestTask>{
      for (final task in remote.tasks)
        if (task.itemRunId != null && task.itemRunId! > 0) task.itemRunId!: task,
    };
    final localIds = local.tasks
        .map((task) => task.itemRunId)
        .whereType<int>()
        .toSet();
    final merged = <MobileLiveTestTask>[];
    for (final task in local.tasks) {
      final id = task.itemRunId;
      if (id == null || id <= 0) {
        merged.add(task);
        continue;
      }
      merged.add(remoteById[id] ?? task);
    }
    for (final task in remote.tasks) {
      final id = task.itemRunId;
      if (id != null && id > 0 && !localIds.contains(id)) {
        merged.add(task);
      }
    }
    return MobileLiveTestSession(
      success: remote.success,
      testMode: remote.testMode,
      skipProjectGates: remote.skipProjectGates || local.skipProjectGates,
      device: remote.device ?? local.device,
      activeRun: remote.activeRun ?? local.activeRun,
      tasks: merged,
      message: remote.message.isNotEmpty ? remote.message : local.message,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    stopSync(notify: false);
    super.dispose();
  }
}
