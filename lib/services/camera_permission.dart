import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../app_theme.dart';

/// Asks for camera access before the camera is opened.
///
/// Shows the system permission prompt when the OS can still show it. If access
/// is denied, restricted, or permanently denied, explains why and opens the
/// app's Settings page on Android and iOS.
Future<bool> ensureCameraPermission(
  BuildContext context, {
  bool includeMicrophone = false,
}) async {
  if (!Platform.isAndroid && !Platform.isIOS) return true;

  var cameraAllowed = false;
  var microphoneAllowed = !includeMicrophone;
  try {
    cameraAllowed = await _requestIfNeeded(Permission.camera);
    if (includeMicrophone) {
      microphoneAllowed = await _requestIfNeeded(Permission.microphone);
    }
  } catch (_) {}

  if (cameraAllowed && microphoneAllowed) return true;
  if (context is! Element || !context.mounted) return false;

  var cameraMissing = !cameraAllowed;
  var microphoneMissing = includeMicrophone && !microphoneAllowed;
  try {
    cameraMissing = !_isAllowed(await Permission.camera.status);
    if (includeMicrophone) {
      microphoneMissing = !_isAllowed(await Permission.microphone.status);
    }
  } catch (_) {}

  if (!cameraMissing && !microphoneMissing) return true;

  final openSettings = await _promptToOpenSettings(
    context,
    cameraMissing: cameraMissing,
    microphoneMissing: microphoneMissing,
  );
  if (openSettings != true) return false;
  await _openSettingsAndWaitForReturn();
  return _hasRequiredAccess(includeMicrophone: includeMicrophone);
}

Future<bool> _hasRequiredAccess({required bool includeMicrophone}) async {
  try {
    final cameraOk = _isAllowed(await Permission.camera.status);
    if (!includeMicrophone) return cameraOk;
    return cameraOk && _isAllowed(await Permission.microphone.status);
  } catch (_) {
    return false;
  }
}

/// Settings opens on top of the app. The listener is attached first so the
/// background transition is not missed, then we wait until the user returns.
Future<void> _openSettingsAndWaitForReturn() async {
  final completer = Completer<void>();
  var sawBackground = false;
  final observer = _ResumeObserver(
    onChange: (state) {
      if (state == AppLifecycleState.inactive ||
          state == AppLifecycleState.hidden ||
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached) {
        sawBackground = true;
        return;
      }
      if (state == AppLifecycleState.resumed &&
          sawBackground &&
          !completer.isCompleted) {
        completer.complete();
      }
    },
  );
  WidgetsBinding.instance.addObserver(observer);
  try {
    await openAppSettings();
    await completer.future.timeout(const Duration(seconds: 3), onTimeout: () {});
    if (!completer.isCompleted && sawBackground) {
      await completer.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () {},
      );
    }
  } finally {
    WidgetsBinding.instance.removeObserver(observer);
    if (!completer.isCompleted) completer.complete();
  }
}

class _ResumeObserver extends WidgetsBindingObserver {
  final void Function(AppLifecycleState state) onChange;

  _ResumeObserver({required this.onChange});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    onChange(state);
  }
}

Future<bool> _requestIfNeeded(Permission permission) async {
  var status = await permission.status;
  if (_isAllowed(status)) return true;
  if (status.isPermanentlyDenied || status.isRestricted) return false;
  status = await permission.request();
  return _isAllowed(status);
}

bool _isAllowed(PermissionStatus status) =>
    status.isGranted || status.isLimited;

Future<bool?> _promptToOpenSettings(
  BuildContext context, {
  required bool cameraMissing,
  required bool microphoneMissing,
}) {
  final String message;
  if (cameraMissing && microphoneMissing) {
    message =
        'Camera and microphone access are required to record video. Open Settings and allow both for this app.';
  } else if (microphoneMissing) {
    message =
        'Microphone access is required to record video. Open Settings and allow the microphone for this app.';
  } else {
    message =
        'Camera access is required to take photos. Open Settings and allow the camera for this app.';
  }

  return showDialog<bool>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: AppTheme.darkBackgroundSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              Icons.photo_camera_rounded,
              color: Color(0xFFEA580C),
              size: 24,
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Permission required',
                style: TextStyle(
                  color: AppTheme.darkTextPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(
            color: AppTheme.mutedGrey,
            fontWeight: FontWeight.w500,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(
                color: AppTheme.mutedGrey,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.navy,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Open Settings'),
          ),
        ],
      );
    },
  );
}
