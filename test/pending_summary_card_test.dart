import 'package:buildAhome/Payments.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final scale in [1.0, 1.3]) {
    testWidgets('NT Pending card with Extra paid fits 360x640 at text scale $scale',
        (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(360, 640),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Wrap(children: [
              debugNtPendingSummaryCard(value: '\u20b9 0', note: 'Extra paid \u20b9 1,23,45,690'),
            ]),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Extra paid'), findsOneWidget);
    });
  }
}
