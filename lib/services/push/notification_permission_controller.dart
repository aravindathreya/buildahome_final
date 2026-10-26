import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../app_navigator.dart';
import 'notification_permission_policy.dart';
import 'push_notification_service.dart';

/// Tracks whether the dashboard should show the notifications-disabled bar.
class NotificationPermissionController {
  NotificationPermissionController._();
  static final NotificationPermissionController instance =
      NotificationPermissionController._();

  static const MethodChannel _channel =
      MethodChannel('buildahome/notification_settings');

  final ValueNotifier<bool> bannerVisible = ValueNotifier<bool>(false);

  /// Uses the real system switch. A granted runtime permission still counts
  /// as off when the user has disabled notifications for this app.
  Future<void> refresh() async {
    if (kIsWeb) {
      bannerVisible.value = false;
      return;
    }
    _listenForResume();
    // Only the newest check may update the banner, so a slow check started
    // while Settings was open cannot overwrite the fresh result.
    final generation = ++_refreshGeneration;
    bool enabled;
    try {
      enabled = await _notificationsEnabled();
    } catch (_) {
      enabled = false;
    }
    if (generation != _refreshGeneration) return;
    bannerVisible.value = NotificationPermissionPolicy.bannerVisible(
      permissionEnabled: enabled,
    );
    if (enabled) {
      // A token sync failure must not bring the banner back.
      try {
        await PushNotificationService.instance.syncTokenForCurrentUser();
      } catch (_) {}
    }
  }

  int _refreshGeneration = 0;
  _ResumeRefresher? _resumeRefresher;

  /// Re-checks the real system setting every time the app comes back to the
  /// foreground (e.g. after the user flips the switch in Settings).
  void _listenForResume() {
    if (_resumeRefresher != null) return;
    _resumeRefresher = _ResumeRefresher(this);
    WidgetsBinding.instance.addObserver(_resumeRefresher!);
  }

  /// Asks for permission, then opens this app's notification settings if
  /// they are still off.
  /// After a denial the OS will not show its dialog again (or showing it
  /// again just annoys the user), so go straight to settings.
  Future<void> enable() async {
    try {
      final status = await Permission.notification.status;
      final canAsk = !askedThisSession &&
          NotificationPermissionPolicy.shouldRequestSystemDialog(
            permissionStatusName: status.name,
          ) &&
          !(Platform.isIOS && status.isDenied);
      if (canAsk) {
        askedThisSession = true;
        await _requestSystemDialog();
      }
    } catch (_) {}
    final enabled = await _notificationsEnabled();
    if (!enabled) {
      await openSettings();
    }
    await refresh();
  }

  static bool askedThisSession = false;
  bool _promptInFlight = false;
  int _missedDialogAttempts = 0;

  /// Asks for the system notification permission once the app is open.
  /// Does not jump into system settings; the banner button does that.
  Future<void> promptOnAppOpen() async {
    if (kIsWeb || askedThisSession || _promptInFlight) return;
    if (_missedDialogAttempts >= 4) {
      askedThisSession = true;
      return;
    }
    _promptInFlight = true;
    try {
      await _waitUntilResumed();
      if (askedThisSession) return;

      final status = await Permission.notification.status;
      if (!NotificationPermissionPolicy.shouldRequestSystemDialog(
        permissionStatusName: status.name,
      )) {
        askedThisSession = true;
        await refresh();
        if (bannerVisible.value) unawaited(_showSettingsPromptOnce());
        return;
      }
      // iOS never shows the system dialog again after a denial.
      if (Platform.isIOS && status.isDenied) {
        askedThisSession = true;
        await refresh();
        if (bannerVisible.value) unawaited(_showSettingsPromptOnce());
        return;
      }

      final presented = await _requestSystemDialog();
      if (presented) {
        askedThisSession = true;
      } else {
        _missedDialogAttempts++;
        if (_missedDialogAttempts >= 4) askedThisSession = true;
      }
      await refresh();
    } catch (e) {
      debugPrint('[Notifications] permission prompt failed: $e');
    } finally {
      _promptInFlight = false;
    }
  }

  /// Client home and staff dashboard both use the app-open prompt.
  Future<void> promptOnClientHome() => promptOnAppOpen();

  Future<void> _waitUntilResumed() async {
    for (var i = 0; i < 25; i++) {
      final state = WidgetsBinding.instance.lifecycleState;
      if (state == null || state == AppLifecycleState.resumed) break;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    // Let the splash / first frame finish so the activity can present a dialog.
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  Future<bool> _requestSystemDialog() async {
    final started = DateTime.now();
    var granted = false;
    try {
      debugPrint('[Notifications] requesting permission');
      // Exactly one system request. Calling several plugins in a row made
      // Android show the dialog twice (a second ask is allowed after one deny).
      if (Platform.isAndroid) {
        final status = await Permission.notification.request();
        if (status.isGranted || status.isLimited) granted = true;
      } else {
        final settings = await FirebaseMessaging.instance.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        if (settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional) {
          granted = true;
        }
      }
    } catch (e) {
      debugPrint('[Notifications] request failed: $e');
    }
    final elapsed = DateTime.now().difference(started).inMilliseconds;
    return NotificationPermissionPolicy.systemDialogWasPresented(
      granted: granted,
      elapsedMilliseconds: elapsed,
    );
  }

  Future<bool> _notificationsEnabled() async {
    // Android 13+ can report the app switch as on before POST_NOTIFICATIONS
    // is granted. The runtime permission is what shows the system dialog.
    // On iOS the native authorization status is the source of truth.
    if (Platform.isAndroid) {
      final runtimeOn = await _runtimePermissionGranted();
      if (runtimeOn == false) return false;
    }
    try {
      final native = await _channel.invokeMethod<bool>('enabled');
      if (native != null) return native;
    } catch (_) {}
    if (Platform.isAndroid) {
      final android = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await android?.areNotificationsEnabled();
      if (enabled != null) return enabled;
    }
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      switch (settings.authorizationStatus) {
        case AuthorizationStatus.authorized:
        case AuthorizationStatus.provisional:
          return true;
        case AuthorizationStatus.denied:
        case AuthorizationStatus.notDetermined:
          return false;
      }
    } catch (_) {}
    final status = await Permission.notification.status;
    return NotificationPermissionPolicy.isEnabledStatusName(status.name);
  }

  /// True when the OS permission is granted, false when it is still off,
  /// null when the plugin could not answer.
  Future<bool?> _runtimePermissionGranted() async {
    try {
      final status = await Permission.notification.status;
      if (NotificationPermissionPolicy.isEnabledStatusName(status.name)) {
        return true;
      }
      final name = status.name.toLowerCase();
      if (name.contains('denied') ||
          name.contains('permanent') ||
          name.contains('restricted')) {
        return false;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static bool _settingsPromptShown = false;

  /// Once per session, after a denial: explain and offer to open settings.
  /// Never awaited by login, so it cannot block sign-in.
  Future<void> _showSettingsPromptOnce() async {
    if (_settingsPromptShown) return;
    final context = globalNavigatorKey.currentContext;
    if (context == null) return;
    _settingsPromptShown = true;
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Notifications are off'),
        content: const Text(
          'Turn on notifications in Settings to get project, task and '
          'payment updates.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
    if (open == true) {
      await openSettings();
      await refresh();
    }
  }

  /// Opens this app's notification settings.
  Future<void> openSettings() async {
    try {
      final opened = await _channel.invokeMethod<bool>('open');
      if (opened == true) return;
    } catch (_) {}
    try {
      await openAppSettings();
    } catch (_) {}
  }
}

class _ResumeRefresher with WidgetsBindingObserver {
  _ResumeRefresher(this.controller);
  final NotificationPermissionController controller;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(controller.refresh());
    }
  }
}
