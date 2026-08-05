import 'package:flutter/material.dart';

/// Which dashboard opened the current route — drives AppBar chrome.
enum DashboardChromeStyle {
  /// Role-colored / navy header (matches Admin Dashboard).
  admin,

  /// White header with navy text (matches User Dashboard).
  user,
}

/// Inherited so feature screens (via [ThemedScaffold]) match the source dashboard.
class DashboardChrome extends InheritedWidget {
  final DashboardChromeStyle style;

  /// Optional AppBar background for [DashboardChromeStyle.admin].
  final Color? appBarColor;

  const DashboardChrome({
    super.key,
    required this.style,
    this.appBarColor,
    required super.child,
  });

  static DashboardChromeStyle of(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<DashboardChrome>()
            ?.style ??
        DashboardChromeStyle.user;
  }

  static Color? appBarColorOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<DashboardChrome>()
        ?.appBarColor;
  }

  static Widget wrap(
    DashboardChromeStyle style,
    Widget child, {
    Color? appBarColor,
  }) {
    return DashboardChrome(
      style: style,
      appBarColor: appBarColor,
      child: child,
    );
  }

  @override
  bool updateShouldNotify(DashboardChrome oldWidget) =>
      style != oldWidget.style || appBarColor != oldWidget.appBarColor;
}
