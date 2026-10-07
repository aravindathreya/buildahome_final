import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

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
    try {
      final enabled = await _notificationsEnabled();
      bannerVisible.value = NotificationPermissionPolicy.bannerVisible(
        permissionEnabled: enabled,
      );
      if (enabled) {
        await PushNotificationService.instance.syncTokenForCurrentUser();
      }
    } catch (_) {
      bannerVisible.value = true;
    }
  }

  /// Asks for permission, then opens this app's notification settings if
  /// they are still off.
  Future<void> enable() async {
    try {
      await Permission.notification.request();
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
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
      final androidGranted = await PushNotificationService.instance
          .requestAndroidNotificationPermission();
      if (androidGranted == true) granted = true;
      final status = await Permission.notification.request();
      if (status.isGranted || status.isLimited) granted = true;
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        granted = true;
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
    final runtimeOn = await _runtimePermissionGranted();
    // Android 13+ can report the app switch as on before POST_NOTIFICATIONS
    // is granted. The runtime permission is what shows the system dialog.
    if (runtimeOn == false) return false;
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
