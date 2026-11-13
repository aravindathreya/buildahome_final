import 'dart:convert';
import 'dart:io';

import 'package:buildAhome/app_navigator.dart';
import 'package:buildAhome/services/camera_capture_recovery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final now = DateTime(2026, 11, 13, 14, 0);

  PendingCameraCapture pendingAt(
    DateTime at, {
    String screen = CameraCaptureScreens.multiMaterialSiteProof,
    String slot = 'delivery',
    String key = '55',
    bool isVideo = false,
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) {
    return PendingCameraCapture.now(
      screen: screen,
      slot: slot,
      key: key,
      isVideo: isVideo,
      extra: extra,
      at: at,
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    CameraCaptureRecovery.debugIsAndroidOverride = true;
    CameraCaptureRecovery.debugLostDataOverride = null;
    CameraCaptureRecovery.debugClearResumers();
  });

  tearDown(() {
    CameraCaptureRecovery.debugIsAndroidOverride = null;
    CameraCaptureRecovery.debugLostDataOverride = null;
    CameraCaptureRecovery.debugClearResumers();
  });

  group('PendingCameraCapture', () {
    test('round-trips through JSON', () {
      final p = pendingAt(
        now,
        isVideo: true,
        slot: 'vehicle',
        extra: {
          'indent_id': '12',
          'task': {'id': 7}
        },
      );
      final back =
          PendingCameraCapture.fromJson(jsonDecode(jsonEncode(p.toJson())))!;
      expect(back.screen, p.screen);
      expect(back.slot, 'vehicle');
      expect(back.key, '55');
      expect(back.isVideo, isTrue);
      expect(back.savedAtMs, now.millisecondsSinceEpoch);
      expect(back.extra['indent_id'], '12');
      expect((back.extra['task'] as Map)['id'], 7);
    });

    test('rejects records without a screen', () {
      expect(PendingCameraCapture.fromJson({'slot': 'x'}), isNull);
      expect(PendingCameraCapture.fromJson('junk'), isNull);
    });
  });

  group('expiry', () {
    test('fresh records are kept, old or undated ones expire', () {
      final ms = now.millisecondsSinceEpoch;
      expect(CameraCaptureRecovery.isExpired(ms, now), isFalse);
      expect(
        CameraCaptureRecovery.isExpired(
          now.subtract(const Duration(minutes: 119)).millisecondsSinceEpoch,
          now,
        ),
        isFalse,
      );
      expect(
        CameraCaptureRecovery.isExpired(
          now
              .subtract(const Duration(hours: 2, minutes: 1))
              .millisecondsSinceEpoch,
          now,
        ),
        isTrue,
      );
      expect(CameraCaptureRecovery.isExpired(0, now), isTrue);
      // Saved "in the future" (clock change) is not trusted either.
      expect(
        CameraCaptureRecovery.isExpired(
          now.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
          now,
        ),
        isTrue,
      );
    });
  });

  group('decideRoute', () {
    const reopenable = {CameraCaptureScreens.multiMaterialSiteProof};

    test('nothing pending', () {
      expect(
        CameraCaptureRecovery.decideRoute(
          null,
          now: now,
          reopenableScreens: reopenable,
        ),
        CameraRecoveryRoute.none,
      );
    });

    test('expired record', () {
      expect(
        CameraCaptureRecovery.decideRoute(
          pendingAt(now.subtract(const Duration(hours: 3))),
          now: now,
          reopenableScreens: reopenable,
        ),
        CameraRecoveryRoute.expired,
      );
    });

    test('site proof is reopened', () {
      expect(
        CameraCaptureRecovery.decideRoute(
          pendingAt(now),
          now: now,
          reopenableScreens: reopenable,
        ),
        CameraRecoveryRoute.reopenScreen,
      );
    });

    test('other screens are stashed', () {
      expect(
        CameraCaptureRecovery.decideRoute(
          pendingAt(now, screen: CameraCaptureScreens.workflowUpload),
          now: now,
          reopenableScreens: reopenable,
        ),
        CameraRecoveryRoute.stash,
      );
    });
  });

  group('pending record', () {
    test('save, read and clear', () async {
      final p = pendingAt(DateTime.now());
      await CameraCaptureRecovery.savePending(p);
      final read = await CameraCaptureRecovery.readPending();
      expect(read?.screen, p.screen);
      expect(await CameraCaptureRecovery.hasPending(), isTrue);
      await CameraCaptureRecovery.clearPending();
      expect(await CameraCaptureRecovery.readPending(), isNull);
    });

    test('expired record is dropped on read', () async {
      await CameraCaptureRecovery.savePending(
        pendingAt(DateTime.now().subtract(const Duration(hours: 5))),
      );
      expect(await CameraCaptureRecovery.readPending(), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(CameraCaptureRecovery.pendingKey), isNull);
    });

    test('runWithPending keeps the record only while the camera is open',
        () async {
      PendingCameraCapture? seenDuringPick;
      final result = await CameraCaptureRecovery.runWithPending<String>(
        pendingAt(DateTime.now()),
        () async {
          seenDuringPick = await CameraCaptureRecovery.readPending();
          return 'photo';
        },
      );
      expect(result, 'photo');
      expect(seenDuringPick, isNotNull);
      expect(await CameraCaptureRecovery.readPending(), isNull);
    });

    test('runWithPending clears the record when the picker throws', () async {
      await expectLater(
        CameraCaptureRecovery.runWithPending<String>(
          pendingAt(DateTime.now()),
          () async => throw StateError('camera failed'),
        ),
        throwsStateError,
      );
      expect(await CameraCaptureRecovery.readPending(), isNull);
    });
  });

  group('takeLostFilesFor', () {
    test('returns lost files for the matching screen and clears', () async {
      await CameraCaptureRecovery.savePending(pendingAt(DateTime.now()));
      CameraCaptureRecovery.debugLostDataOverride =
          () async => [XFile('/tmp/a.jpg')];
      final files = await CameraCaptureRecovery.takeLostFilesFor(
        CameraCaptureScreens.multiMaterialSiteProof,
      );
      expect(files.map((f) => f.path), ['/tmp/a.jpg']);
      expect(await CameraCaptureRecovery.readPending(), isNull);
    });

    test('leaves another screen\'s record alone', () async {
      await CameraCaptureRecovery.savePending(
        pendingAt(DateTime.now(), screen: CameraCaptureScreens.chat),
      );
      var called = false;
      CameraCaptureRecovery.debugLostDataOverride = () async {
        called = true;
        return [XFile('/tmp/a.jpg')];
      };
      final files = await CameraCaptureRecovery.takeLostFilesFor(
        CameraCaptureScreens.multiMaterialSiteProof,
      );
      expect(files, isEmpty);
      expect(called, isFalse);
      expect(await CameraCaptureRecovery.readPending(), isNotNull);
    });
  });

  group('stash', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('cam_recovery_test');
    });
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    String makeFile(String name) {
      final f = File('${dir.path}${Platform.pathSeparator}$name')
        ..writeAsStringSync('x');
      return f.path;
    }

    test('hands the file back once, only to the same screen and key', () async {
      final path = makeFile('a.jpg');
      await CameraCaptureRecovery.stashRecovered(
        pendingAt(
          DateTime.now(),
          screen: CameraCaptureScreens.workflowUpload,
          key: '10:upload',
          slot: '',
        ),
        [path],
      );
      expect(
        await CameraCaptureRecovery.takeRecovered(
          screen: CameraCaptureScreens.workflowUpload,
          key: '11:upload',
        ),
        isNull,
      );
      expect(
        await CameraCaptureRecovery.takeRecovered(
          screen: CameraCaptureScreens.chat,
          key: '10:upload',
        ),
        isNull,
      );
      final got = await CameraCaptureRecovery.takeRecovered(
        screen: CameraCaptureScreens.workflowUpload,
        key: '10:upload',
      );
      expect(got?.paths, [path]);
      expect(
        await CameraCaptureRecovery.takeRecovered(
          screen: CameraCaptureScreens.workflowUpload,
          key: '10:upload',
        ),
        isNull,
      );
    });

    test('slot filter', () async {
      final path = makeFile('v.jpg');
      await CameraCaptureRecovery.stashRecovered(
        pendingAt(DateTime.now(), slot: 'vehicle'),
        [path],
      );
      expect(
        await CameraCaptureRecovery.takeRecovered(
          screen: CameraCaptureScreens.multiMaterialSiteProof,
          key: '55',
          slot: 'delivery',
        ),
        isNull,
      );
      final got = await CameraCaptureRecovery.takeRecovered(
        screen: CameraCaptureScreens.multiMaterialSiteProof,
        key: '55',
        slot: 'vehicle',
      );
      expect(got?.pending.slot, 'vehicle');
    });

    test('expired entries and missing files are dropped', () async {
      final path = makeFile('old.jpg');
      await CameraCaptureRecovery.stashRecovered(
        pendingAt(
          DateTime.now().subtract(const Duration(hours: 3)),
          screen: CameraCaptureScreens.paymentProof,
          key: '',
        ),
        [path],
      );
      expect(
        await CameraCaptureRecovery.takeRecovered(
          screen: CameraCaptureScreens.paymentProof,
        ),
        isNull,
      );
      await CameraCaptureRecovery.stashRecovered(
        pendingAt(
          DateTime.now(),
          screen: CameraCaptureScreens.paymentProof,
          key: '',
        ),
        ['${dir.path}${Platform.pathSeparator}gone.jpg'],
      );
      expect(
        await CameraCaptureRecovery.takeRecovered(
          screen: CameraCaptureScreens.paymentProof,
        ),
        isNull,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(CameraCaptureRecovery.recoveredKey), isNull);
    });
  });

  group('resumeIfPending', () {
    Future<BuildContext> pumpApp(WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: globalScaffoldMessengerKey,
          home: Scaffold(
            body: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      return ctx;
    }

    testWidgets('reopens a registered screen', (tester) async {
      final ctx = await pumpApp(tester);
      PendingCameraCapture? reopened;
      CameraCaptureRecovery.registerResumer(
        CameraCaptureScreens.multiMaterialSiteProof,
        (context, pending) async => reopened = pending,
      );
      final route = await tester.runAsync(() async {
        await CameraCaptureRecovery.savePending(pendingAt(DateTime.now()));
        return CameraCaptureRecovery.resumeIfPending(ctx);
      });
      expect(route, CameraRecoveryRoute.reopenScreen);
      expect(reopened?.key, '55');
    });

    testWidgets('stashes lost files for screens without a resumer',
        (tester) async {
      final ctx = await pumpApp(tester);
      CameraCaptureRecovery.debugLostDataOverride =
          () async => [XFile('/tmp/lost.jpg')];
      final route = await tester.runAsync(() async {
        await CameraCaptureRecovery.savePending(
          pendingAt(
            DateTime.now(),
            screen: CameraCaptureScreens.workflowUpload,
            key: '1:a',
          ),
        );
        return CameraCaptureRecovery.resumeIfPending(ctx);
      });
      await tester.pump();
      expect(route, CameraRecoveryRoute.stash);
      final got = await tester.runAsync(
        () => CameraCaptureRecovery.takeRecovered(
          screen: CameraCaptureScreens.workflowUpload,
          key: '1:a',
          checkFilesExist: false,
        ),
      );
      expect(got?.paths, ['/tmp/lost.jpg']);
      expect(
        await tester.runAsync(CameraCaptureRecovery.readPending),
        isNull,
      );
      expect(find.textContaining('camera was open'), findsOneWidget);
    });

    testWidgets('does not stash for screens that cannot restore',
        (tester) async {
      final ctx = await pumpApp(tester);
      CameraCaptureRecovery.debugLostDataOverride =
          () async => [XFile('/tmp/lost.jpg')];
      await tester.runAsync(() async {
        await CameraCaptureRecovery.savePending(
          pendingAt(
            DateTime.now(),
            screen: CameraCaptureScreens.pictureChoice,
            key: '',
            extra: CameraCaptureRecovery.notRestorableExtra,
          ),
        );
        await CameraCaptureRecovery.resumeIfPending(ctx);
      });
      await tester.pump();
      final prefs = await tester.runAsync(SharedPreferences.getInstance);
      expect(prefs!.getString(CameraCaptureRecovery.recoveredKey), isNull);
      expect(find.textContaining('take it again'), findsOneWidget);
    });

    testWidgets('expired record is cleared without routing', (tester) async {
      final ctx = await pumpApp(tester);
      var called = false;
      CameraCaptureRecovery.registerResumer(
        CameraCaptureScreens.multiMaterialSiteProof,
        (context, pending) async => called = true,
      );
      final route = await tester.runAsync(() async {
        await CameraCaptureRecovery.savePending(
          pendingAt(DateTime.now().subtract(const Duration(hours: 4))),
        );
        return CameraCaptureRecovery.resumeIfPending(ctx);
      });
      expect(route, CameraRecoveryRoute.expired);
      expect(called, isFalse);
      final prefs = await tester.runAsync(SharedPreferences.getInstance);
      expect(prefs!.getString(CameraCaptureRecovery.pendingKey), isNull);
    });
  });
}
