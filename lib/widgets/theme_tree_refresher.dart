import 'package:flutter/material.dart';

import '../services/theme_service.dart';

/// Rebuilds the live screen tree when light/dark changes.
///
/// Most screens read [AppTheme] colors directly. Those values update only when
/// the widget builds again, and a theme change alone does not rebuild routes
/// that never called [Theme.of].
class ThemeTreeRefresher extends StatefulWidget {
  const ThemeTreeRefresher({super.key, required this.child});

  final Widget child;

  @override
  State<ThemeTreeRefresher> createState() => _ThemeTreeRefresherState();
}

class _ThemeTreeRefresherState extends State<ThemeTreeRefresher> {
  @override
  void initState() {
    super.initState();
    ThemeService.instance.modeNotifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    ThemeService.instance.modeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (!mounted) return;
    void mark(Element element) {
      if (!element.mounted) return;
      element.markNeedsBuild();
      element.visitChildren(mark);
    }

    mark(context as Element);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
