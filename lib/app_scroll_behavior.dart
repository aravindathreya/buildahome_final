import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Lighter flings and stretch overscroll so lists track the finger more easily.
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.mouse,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    switch (getPlatform(context)) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return const BouncingScrollPhysics(
          parent: AppScrollPhysics(),
        );
      default:
        return const AppScrollPhysics(parent: ClampingScrollPhysics());
    }
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    switch (getPlatform(context)) {
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return child;
      default:
        return StretchingOverscrollIndicator(
          axisDirection: details.direction,
          child: child,
        );
    }
  }
}

class AppScrollPhysics extends ScrollPhysics {
  const AppScrollPhysics({super.parent});

  @override
  AppScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return AppScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  double get minFlingDistance => 8;

  @override
  double get minFlingVelocity => 30;

  @override
  double get maxFlingVelocity => 25000;

  @override
  SpringDescription get spring => SpringDescription.withDampingRatio(
        mass: 0.45,
        stiffness: 140,
        ratio: 1.05,
      );
}
