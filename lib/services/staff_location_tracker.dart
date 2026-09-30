import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'attendance_service.dart';
import 'location_service.dart';

/// Shares a staff member's location only while they are clocked in.
///
/// Polling starts after check-in and stops on check-out. A timer posts every
/// 15 minutes during that window. On Android a foreground location service
/// keeps that going when the app is in the background. On iOS this needs
/// Always location permission.
class StaffLocationTracker with WidgetsBindingObserver {
  StaffLocationTracker._();

  static final StaffLocationTracker instance = StaffLocationTracker._();

  static const Duration pollInterval = Duration(minutes: 15);

  Timer? _timer;
  StreamSubscription<Position>? _positionSub;
  bool _started = false;
  bool _pingInFlight = false;
  DateTime? _lastSentAt;
  int _generation = 0;

  /// Starts polling when today's attendance is still open, and stops it
  /// after check-out. Safe to call on launch and whenever the app resumes.
  Future<void> syncWithShift() async {
    if (!await _isStaffSession()) {
      stop();
      return;
    }

    final generation = ++_generation;
    try {
      final status = await AttendanceService.getStatus();
      if (generation != _generation) return;
      if (status.canCheckOut) {
        if (_started) {
          unawaited(_ping());
        } else {
          await start();
        }
      } else {
        stop();
      }
    } catch (e) {
      debugPrint('[LocationTracker] shift sync failed: $e');
    }
  }

  Future<void> start() async {
    if (_started) return;
    if (!await _isStaffSession()) return;

    final generation = ++_generation;
    _started = true;
    WidgetsBinding.instance.addObserver(this);

    final backgroundGranted = await LocationService.requestBackgroundAccess();
    if (generation != _generation || !_started) return;

    if (!backgroundGranted) {
      debugPrint(
        '[LocationTracker] background permission not granted; '
        'updates continue while the app is open',
      );
    }

    if (Platform.isAndroid) {
      final notifications = await Permission.notification.status;
      if (!notifications.isGranted) {
        await Permission.notification.request();
      }
    }
    if (generation != _generation || !_started) return;

    await _ping(ignoreThrottle: true);
    if (generation != _generation || !_started) return;
    _timer?.cancel();
    _timer = Timer.periodic(pollInterval, (_) {
      unawaited(_ping());
    });
    if (backgroundGranted) {
      _listenForBackgroundUpdates();
    }
  }

  void stop() {
    _generation++;
    _started = false;
    _timer?.cancel();
    _timer = null;
    _positionSub?.cancel();
    _positionSub = null;
    _lastSentAt = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(syncWithShift());
    }
  }

  Future<bool> _isStaffSession() async {
    final prefs = await SharedPreferences.getInstance();
    final role = (prefs.getString('role') ?? '').trim().toLowerCase();
    final token = prefs.getString('api_token')?.trim();
    if (role.isEmpty || role == 'client') return false;
    if (token == null || token.isEmpty || token.toLowerCase() == 'null') {
      return false;
    }
    return true;
  }

  void _listenForBackgroundUpdates() {
    if (!_started) return;
    _positionSub?.cancel();
    final LocationSettings settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.medium,
            distanceFilter: 0,
            intervalDuration: pollInterval,
            foregroundNotificationConfig: const ForegroundNotificationConfig(
              notificationTitle: 'Attendance location',
              notificationText:
                  'Sharing your location every 15 minutes until you check out',
              notificationChannelName: 'Attendance location',
              notificationIcon: AndroidResource(
                name: 'ic_notification',
                defType: 'drawable',
              ),
              setOngoing: true,
              enableWakeLock: true,
            ),
          )
        : AppleSettings(
            accuracy: LocationAccuracy.medium,
            distanceFilter: 0,
            activityType: ActivityType.other,
            pauseLocationUpdatesAutomatically: false,
            showBackgroundLocationIndicator: true,
            allowBackgroundLocationUpdates: true,
          );

    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(
      (position) {
        unawaited(_send(position));
      },
      onError: (Object error) {
        debugPrint('[LocationTracker] stream error: $error');
      },
    );
  }

  Future<void> _ping({bool ignoreThrottle = false}) async {
    if (!_started) return;
    if (!ignoreThrottle && !_isDue) return;

    if (!ignoreThrottle) {
      try {
        final status = await AttendanceService.getStatus();
        if (!_started) return;
        if (!status.canCheckOut) {
          debugPrint('[LocationTracker] shift ended; stopping');
          stop();
          return;
        }
      } catch (e) {
        debugPrint('[LocationTracker] status check failed: $e');
      }
    }

    final result = await LocationService.getCurrentPosition();
    if (!result.ok || result.position == null) {
      debugPrint('[LocationTracker] skip ping: ${result.error}');
      return;
    }
    await _send(result.position!, ignoreThrottle: ignoreThrottle);
  }

  bool get _isDue {
    final last = _lastSentAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= pollInterval;
  }

  Future<void> _send(Position position, {bool ignoreThrottle = false}) async {
    if (!_started || _pingInFlight) return;
    if (!ignoreThrottle && !_isDue) return;

    _pingInFlight = true;
    try {
      await AttendanceService.updateLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
      _lastSentAt = DateTime.now();
      debugPrint(
        '[LocationTracker] updated '
        '${position.latitude}, ${position.longitude}',
      );
    } catch (e) {
      debugPrint('[LocationTracker] update failed: $e');
    } finally {
      _pingInFlight = false;
    }
  }
}
