import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_navigator.dart';
import '../widgets/in_app_photo_capture.dart';

/// Android can kill the app while the phone's own camera app is open (low
/// memory). Flutter then cold-starts on the splash/dashboard and the picked
/// photo or video only comes back through `ImagePicker.retrieveLostData()`.
///
/// This helper is shared by every live-camera upload:
/// * [capturePhoto] prefers the in-app camera on Android (the app stays in the
///   foreground, so it can't be killed). If that can't open it falls back to
///   the phone's camera app with a downscaled image.
/// * Before the phone's camera app opens, a [PendingCameraCapture] is saved.
///   It is cleared as soon as the picker returns normally.
/// * On the next start the dashboard calls [resumeIfPending]. Screens that can
///   be reopened directly (registered resumers) are pushed again and restore
///   the capture themselves via [retrieveLostFiles]. Other screens get the
///   recovered file stashed; they pick it up with [takeRecovered] the next
///   time the user opens the same task/screen.
class PendingCameraCapture {
  /// Screen id, e.g. [CameraCaptureScreens.multiMaterialSiteProof].
  final String screen;

  /// Which list/field on that screen the file belongs to (e.g. 'delivery').
  final String slot;

  /// Optional identity of the record on that screen (task id, conversation
  /// id...). [takeRecovered] only hands the file back to the same key.
  final String key;

  final bool isVideo;
  final int savedAtMs;

  /// Anything the screen needs to reopen itself after a restart.
  final Map<String, dynamic> extra;

  const PendingCameraCapture({
    required this.screen,
    this.slot = '',
    this.key = '',
    this.isVideo = false,
    required this.savedAtMs,
    this.extra = const <String, dynamic>{},
  });

  factory PendingCameraCapture.now({
    required String screen,
    String slot = '',
    String key = '',
    bool isVideo = false,
    Map<String, dynamic> extra = const <String, dynamic>{},
    DateTime? at,
  }) {
    return PendingCameraCapture(
      screen: screen,
      slot: slot,
      key: key,
      isVideo: isVideo,
      savedAtMs: (at ?? DateTime.now()).millisecondsSinceEpoch,
      extra: extra,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'screen': screen,
        'slot': slot,
        'key': key,
        'is_video': isVideo,
        'saved_at': savedAtMs,
        'extra': extra,
      };

  static PendingCameraCapture? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final screen = raw['screen']?.toString().trim() ?? '';
    if (screen.isEmpty) return null;
    final extraRaw = raw['extra'];
    return PendingCameraCapture(
      screen: screen,
      slot: raw['slot']?.toString() ?? '',
      key: raw['key']?.toString() ?? '',
      isVideo: raw['is_video'] == true,
      savedAtMs: int.tryParse('${raw['saved_at'] ?? ''}') ?? 0,
      extra: extraRaw is Map
          ? Map<String, dynamic>.from(extraRaw)
          : const <String, dynamic>{},
    );
  }
}

/// Files recovered after a restart, waiting for their screen to reopen.
class RecoveredCameraCapture {
  final PendingCameraCapture pending;
  final List<String> paths;

  const RecoveredCameraCapture({required this.pending, required this.paths});

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...pending.toJson(),
        'paths': paths,
      };

  static RecoveredCameraCapture? fromJson(Object? raw) {
    final pending = PendingCameraCapture.fromJson(raw);
    if (pending == null || raw is! Map) return null;
    final pathsRaw = raw['paths'];
    final paths = pathsRaw is List
        ? pathsRaw.map((e) => '$e').where((e) => e.isNotEmpty).toList()
        : <String>[];
    return RecoveredCameraCapture(pending: pending, paths: paths);
  }
}

/// Screen ids used in pending records.
class CameraCaptureScreens {
  static const multiMaterialSiteProof = 'multi_material_site_proof';
  static const workflowUpload = 'workflow_upload';
  static const pictureChoice = 'picture_choice';
  static const chat = 'chat';
  static const paymentProof = 'payment_proof';
  static const clientPaymentProof = 'client_payment_proof';
  static const inspectionRequest = 'inspection_request';
  static const requestDrawing = 'request_drawing';
  static const siteVisitReports = 'site_visit_reports';
  static const testReports = 'test_reports';
  static const notesAndComments = 'notes_and_comments';
}

/// What [CameraCaptureRecovery.resumeIfPending] does with a pending record.
enum CameraRecoveryRoute {
  /// Nothing pending.
  none,

  /// Too old (or missing a time); drop it.
  expired,

  /// A resumer is registered: reopen that screen to restore the capture.
  reopenScreen,

  /// No resumer: keep the recovered file until the screen is opened again.
  stash,
}

typedef CameraCaptureResumer = Future<void> Function(
  BuildContext context,
  PendingCameraCapture pending,
);

class CameraCaptureRecovery {
  CameraCaptureRecovery._();

  static const String pendingKey = 'camera_capture_pending_v1';
  static const String recoveredKey = 'camera_capture_recovered_v1';
  static const Duration maxAge = Duration(hours: 2);

  /// Longest edge for live photos taken through the phone's camera app.
  static const double photoMaxEdge = 2000;

  /// For screens that can't take a recovered file back: after a restart the
  /// user is only told to take the photo again.
  static const Map<String, dynamic> notRestorableExtra = <String, dynamic>{
    'no_restore': true,
    'restore_hint': 'The app restarted while the camera was open, so the '
        'photo could not be kept. Please take it again.',
  };

  /// Test hook: pretend to be Android (retrieveLostData only works there).
  @visibleForTesting
  static bool? debugIsAndroidOverride;

  /// Test hook: replaces `ImagePicker().retrieveLostData()`.
  @visibleForTesting
  static Future<List<XFile>> Function()? debugLostDataOverride;

  static bool get _isAndroid =>
      debugIsAndroidOverride ?? (!kIsWeb && Platform.isAndroid);

  static bool isExpired(
    int savedAtMs,
    DateTime now, {
    Duration maxAge = CameraCaptureRecovery.maxAge,
  }) {
    if (savedAtMs <= 0) return true;
    final age = now.millisecondsSinceEpoch - savedAtMs;
    return age < 0 || age > maxAge.inMilliseconds;
  }

  /// Pure routing decision, unit-tested.
  static CameraRecoveryRoute decideRoute(
    PendingCameraCapture? pending, {
    required DateTime now,
    required Set<String> reopenableScreens,
  }) {
    if (pending == null) return CameraRecoveryRoute.none;
    if (isExpired(pending.savedAtMs, now)) return CameraRecoveryRoute.expired;
    if (reopenableScreens.contains(pending.screen)) {
      return CameraRecoveryRoute.reopenScreen;
    }
    return CameraRecoveryRoute.stash;
  }

  // ---------------------------------------------------------------- pending

  static Future<void> savePending(PendingCameraCapture pending) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(pendingKey, jsonEncode(pending.toJson()));
  }

  /// The pending record, or null. Expired records are removed.
  static Future<PendingCameraCapture?> readPending({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(pendingKey);
    if (raw == null || raw.isEmpty) return null;
    PendingCameraCapture? pending;
    try {
      pending = PendingCameraCapture.fromJson(jsonDecode(raw));
    } catch (_) {}
    if (pending == null ||
        isExpired(pending.savedAtMs, now ?? DateTime.now())) {
      await prefs.remove(pendingKey);
      return null;
    }
    return pending;
  }

  static Future<bool> hasPending() async => (await readPending()) != null;

  static Future<void> clearPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(pendingKey);
  }

  /// Saves [pending], runs [pick] (which opens the phone's camera app) and
  /// clears the record once the picker returns: if we are still running,
  /// nothing needs recovering.
  static Future<T?> runWithPending<T>(
    PendingCameraCapture pending,
    Future<T?> Function() pick,
  ) async {
    await savePending(pending);
    try {
      return await pick();
    } finally {
      await clearPending();
    }
  }

  // ---------------------------------------------------------------- capture

  /// Live photo. On Android uses [InAppPhotoCapturePage] first; falls back to
  /// the phone's camera app (downscaled, with a pending record). Camera only,
  /// never the gallery. Returns null when the user cancels.
  static Future<XFile?> capturePhoto(
    BuildContext context, {
    required PendingCameraCapture pending,
    int imageQuality = 88,
    double maxEdge = photoMaxEdge,
    double? maxWidth,
    double? maxHeight,
    bool preferInAppCamera = true,
  }) async {
    if (preferInAppCamera && _isAndroid) {
      final result = await Navigator.of(context).push<Object?>(
        MaterialPageRoute(builder: (_) => const InAppPhotoCapturePage()),
      );
      if (result is XFile) return result;
      if (result != 'fallback') return null; // closed by the user
      if (!context.mounted) return null;
    }
    return runWithPending<XFile>(
      pending,
      () => ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: imageQuality,
        maxWidth: maxWidth ?? maxEdge,
        maxHeight: maxHeight ?? maxEdge,
      ),
    );
  }

  /// Live video through the phone's camera app, with a pending record.
  static Future<XFile?> recordVideo({
    required PendingCameraCapture pending,
    Duration? maxDuration,
  }) {
    return runWithPending<XFile>(
      pending,
      () => ImagePicker().pickVideo(
        source: ImageSource.camera,
        maxDuration: maxDuration,
      ),
    );
  }

  /// Android: the photo/video picked just before the app was killed.
  static Future<List<XFile>> retrieveLostFiles() async {
    final override = debugLostDataOverride;
    if (override != null) return override();
    if (!_isAndroid) return const <XFile>[];
    try {
      final response = await ImagePicker().retrieveLostData();
      if (response.isEmpty) return const <XFile>[];
      return response.files ?? const <XFile>[];
    } catch (e) {
      debugPrint('[CameraCaptureRecovery] retrieveLostData failed: $e');
      return const <XFile>[];
    }
  }

  /// For a screen reopened by its resumer: the lost files for [screen], and
  /// the pending record is cleared. Empty when the pending record belongs to
  /// another screen (that screen keeps its record).
  static Future<List<XFile>> takeLostFilesFor(String screen) async {
    final pending = await readPending();
    if (pending == null || pending.screen != screen) return const <XFile>[];
    final files = await retrieveLostFiles();
    await clearPending();
    return files;
  }

  // ------------------------------------------------------------------ stash

  static Future<List<RecoveredCameraCapture>> _readStash(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(recoveredKey);
    if (raw == null || raw.isEmpty) return <RecoveredCameraCapture>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .map(RecoveredCameraCapture.fromJson)
            .whereType<RecoveredCameraCapture>()
            .toList();
      }
    } catch (_) {}
    return <RecoveredCameraCapture>[];
  }

  static Future<void> _writeStash(
    SharedPreferences prefs,
    List<RecoveredCameraCapture> items,
  ) async {
    if (items.isEmpty) {
      await prefs.remove(recoveredKey);
      return;
    }
    await prefs.setString(
      recoveredKey,
      jsonEncode(items.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> stashRecovered(
    PendingCameraCapture pending,
    List<String> paths,
  ) async {
    if (paths.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final items = await _readStash(prefs);
    items.removeWhere(
      (e) =>
          e.pending.screen == pending.screen &&
          e.pending.key == pending.key &&
          e.pending.slot == pending.slot,
    );
    items.add(RecoveredCameraCapture(pending: pending, paths: paths));
    await _writeStash(prefs, items);
  }

  /// Hands back (and removes) files recovered for [screen] and [key]. Pass
  /// [slot] to match only that slot. Expired entries and missing files are
  /// dropped.
  static Future<RecoveredCameraCapture?> takeRecovered({
    required String screen,
    String key = '',
    String? slot,
    DateTime? now,
    bool checkFilesExist = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final items = await _readStash(prefs);
    if (items.isEmpty) return null;
    final at = now ?? DateTime.now();
    items.removeWhere((e) => isExpired(e.pending.savedAtMs, at));
    RecoveredCameraCapture? found;
    for (final item in items) {
      if (item.pending.screen != screen || item.pending.key != key) continue;
      if (slot != null && item.pending.slot != slot) continue;
      found = item;
      break;
    }
    if (found != null) items.remove(found);
    await _writeStash(prefs, items);
    if (found == null) return null;
    final paths = checkFilesExist
        ? found.paths.where((p) => File(p).existsSync()).toList()
        : found.paths;
    if (paths.isEmpty) return null;
    return RecoveredCameraCapture(pending: found.pending, paths: paths);
  }

  // ----------------------------------------------------------------- resume

  static final Map<String, CameraCaptureResumer> _resumers =
      <String, CameraCaptureResumer>{};

  /// Screens that can be pushed again from the dashboard after a restart.
  static void registerResumer(String screen, CameraCaptureResumer resumer) {
    _resumers[screen] = resumer;
  }

  @visibleForTesting
  static void debugClearResumers() => _resumers.clear();

  static bool _resuming = false;

  /// Called by the dashboards on start (next to the daily update recovery).
  static Future<CameraRecoveryRoute> resumeIfPending(
    BuildContext context, {
    DateTime? now,
  }) async {
    if (_resuming) return CameraRecoveryRoute.none;
    _resuming = true;
    try {
      final at = now ?? DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(pendingKey);
      PendingCameraCapture? pending;
      if (raw != null && raw.isNotEmpty) {
        try {
          pending = PendingCameraCapture.fromJson(jsonDecode(raw));
        } catch (_) {}
      }
      final route = decideRoute(
        pending,
        now: at,
        reopenableScreens: _resumers.keys.toSet(),
      );
      switch (route) {
        case CameraRecoveryRoute.none:
          if (raw != null) await clearPending();
          break;
        case CameraRecoveryRoute.expired:
          await clearPending();
          break;
        case CameraRecoveryRoute.reopenScreen:
          if (!context.mounted) break;
          // The screen calls takeLostFilesFor() and clears the record.
          await _resumers[pending!.screen]!(context, pending);
          break;
        case CameraRecoveryRoute.stash:
          final files = await retrieveLostFiles();
          await clearPending();
          final paths = files.map((f) => f.path).toList();
          if (paths.isNotEmpty) {
            if (pending!.extra['no_restore'] != true) {
              await stashRecovered(pending, paths);
            }
            final hint = pending.extra['restore_hint']?.toString().trim();
            globalScaffoldMessengerKey.currentState?.showSnackBar(
              SnackBar(
                content: Text(
                  (hint != null && hint.isNotEmpty)
                      ? hint
                      : 'The app restarted while the camera was open. Your '
                          '${pending.isVideo ? 'video' : 'photo'} was saved. '
                          'Open the same screen again to continue.',
                ),
                duration: const Duration(seconds: 6),
              ),
            );
          }
          break;
      }
      return route;
    } finally {
      _resuming = false;
    }
  }
}
