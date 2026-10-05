import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buildAhome/models/sales_sop_slot.dart';
import 'package:buildAhome/slots/site_visits_ui.dart';
import 'package:buildAhome/slots/site_visit_booking.dart';

SalesSopSlot fixture(
        {String status = 'awaiting_confirmation', bool required = false}) =>
    SalesSopSlot.fromJson({
      'id': 'visit1',
      'title': 'Site Inspection',
      'source': 'site_inspection',
      'status': status,
      'can_accept': true,
      'given_by': 'Test G',
      'presence_label': 'At site',
      'require_note': required,
      'allow_note': true,
      'options': [
        {
          'index': 1,
          'datetime': '2030-09-13T10:00:00',
          'display': 'Fri, 13 September 2030 · 10:00 AM',
          'time_label': '10:00 AM'
        },
        {
          'index': 2,
          'datetime': '2030-09-13T11:30:00',
          'display': 'Fri, 13 September 2030 · 11:30 AM',
          'time_label': '11:30 AM'
        },
        {
          'index': 3,
          'datetime': '2030-09-14T16:00:00',
          'display': 'Sat, 14 September 2030 · 04:00 PM',
          'time_label': '04:00 PM'
        },
      ],
    });
Future<void> capture(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('preview')));
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/site_visits_preview')
      ..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> show(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('preview'),
      child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: visitsTheme(),
          home: child)));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final font = FontLoader('Mulish-Regular')
      ..addFont(rootBundle.load('assets/fonts/Mulish/Mulish-Regular.ttf'));
    await font.load();
    var sdkDir = File(Platform.resolvedExecutable).parent;
    while (
        !File('${sdkDir.path}/artifacts/material_fonts/materialicons-regular.otf')
                .existsSync() &&
            sdkDir.parent.path != sdkDir.path) {
      sdkDir = sdkDir.parent;
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(File(
              '${sdkDir.path}/artifacts/material_fonts/materialicons-regular.otf')
          .readAsBytes()
          .then((bytes) => ByteData.sublistView(bytes)));
    await icons.load();
  });
  testWidgets('overview filters and uses actual server statuses',
      (tester) async {
    final pending = fixture();
    await show(
        tester,
        Scaffold(
            body: SiteVisitsOverview(
                slots: [
              pending,
              pending.copyWith(
                  id: 'visit2',
                  title: 'Kitchen visit',
                  status: 'accepted',
                  acceptedSlot: pending.options[1]),
              pending.copyWith(
                  id: 'visit3', title: 'Final inspection', status: 'completed')
            ],
                onRefresh: () async {},
                onOpen: (_) {},
                onDetails: () {},
                onHelp: () {})));
    expect(find.text('1 confirmed · 1 pending'), findsOneWidget);
    await capture(tester, 'overview');
    await tester.tap(find.text('Completed (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Final inspection'), findsOneWidget);
    expect(find.text('Site Inspection'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('date-time-review-success submits exact option only on confirm',
      (tester) async {
    var calls = 0;
    int? submitted;
    String? comment;
    await show(
        tester,
        SiteVisitBooking(
            slot: fixture(required: true),
            onSubmit: (index, choices, note) async {
              calls++;
              submitted = index;
              comment = note;
            }));
    await capture(tester, 'date');
    await tester.tap(find.text('13'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('11:30 AM'));
    await tester.pumpAndSettle();
    await capture(tester, 'time');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.text('Confirm slot'));
    await tester.pumpAndSettle();
    expect(find.text('A comment is required.'), findsOneWidget);
    expect(calls, 0);
    await tester.enterText(find.byType(TextField), 'Use gate 2');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await capture(tester, 'review');
    await tester.tap(find.text('Confirm slot'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(submitted, 2);
    expect(comment, 'Use gate 2');
    expect(find.text('Visit slot confirmed'), findsOneWidget);
    await capture(tester, 'success');
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed request retains review and never shows success',
      (tester) async {
    await show(
        tester,
        SiteVisitBooking(
            slot: fixture(),
            initialIndex: 2,
            onSubmit: (_, __, ___) async {
              throw Exception('This slot is no longer available');
            }));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm slot'));
    await tester.pumpAndSettle();
    expect(find.text('This slot is no longer available'), findsOneWidget);
    expect(find.text('Visit slot confirmed'), findsNothing);
  });
  testWidgets(
      'multiple preferred times retain server count and submitted wording',
      (tester) async {
    final slot = fixture().copyWith(
        status: 'needs_selection',
        canAccept: false,
        canSelect: true,
        slotCount: 2);
    List<VisitPreference>? payload;
    await show(
        tester,
        SiteVisitBooking(
            slot: slot,
            selectPreferred: true,
            initialPreferences: [
              VisitPreference(DateTime(2030, 9, 13, 10), null),
              VisitPreference(DateTime(2030, 9, 14, 11), null)
            ],
            onSubmit: (_, choices, __) async {
              payload = choices;
            }));
    expect(find.text('2 of 2 preferred times selected'), findsOneWidget);
    await tester.tap(find.text('Submit preferred slots'));
    await tester.pumpAndSettle();
    expect(payload!.length, 2);
    expect(find.text('Preferred slots submitted'), findsOneWidget);
    expect(find.text('Visit slot confirmed'), findsNothing);
  });
}
