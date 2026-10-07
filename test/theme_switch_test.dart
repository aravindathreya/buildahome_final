import 'package:buildAhome/app_theme.dart';
import 'package:buildAhome/services/theme_service.dart';
import 'package:buildAhome/widgets/theme_tree_refresher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
    await ThemeService.instance.setDark(true);
  });

  test('light and dark themes can interpolate', () {
    expect(
      () => ThemeData.lerp(
        AppTheme.getLightTheme(),
        AppTheme.getDarkTheme(),
        0.5,
      ),
      returnsNormally,
    );
  });

  testWidgets('theme toggle updates screens and does not throw',
      (tester) async {
    await tester.pumpWidget(
      ValueListenableBuilder<ThemeMode>(
        valueListenable: ThemeService.instance.modeNotifier,
        builder: (context, themeMode, _) {
          return MaterialApp(
            theme: AppTheme.getLightTheme(),
            darkTheme: AppTheme.getDarkTheme(),
            themeMode: themeMode,
            themeAnimationDuration: Duration.zero,
            builder: (context, child) {
              return ThemeTreeRefresher(
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const _ThemeProbe(),
          );
        },
      ),
    );
    await tester.pump();

    Color probeColor() =>
        tester.widget<ColoredBox>(find.byKey(const Key('theme-probe'))).color;

    expect(probeColor(), AppTheme.backgroundPrimary);
    expect(ThemeService.instance.isDark, isTrue);

    await ThemeService.instance.setDark(false);
    await tester.pump();
    expect(ThemeService.instance.isDark, isFalse);
    expect(probeColor(), AppTheme.lightBackgroundPrimary);
    expect(tester.takeException(), isNull);

    await ThemeService.instance.setDark(true);
    await tester.pump();
    expect(ThemeService.instance.isDark, isTrue);
    expect(probeColor(), const Color(0xFF121212));
    expect(tester.takeException(), isNull);
  });
}

class _ThemeProbe extends StatelessWidget {
  const _ThemeProbe();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        children: [
          ColoredBox(
            key: const Key('theme-probe'),
            color: AppTheme.backgroundPrimary,
            child: const SizedBox(width: 20, height: 20),
          ),
          const ListTile(title: Text('Appearance'), subtitle: Text('Mode')),
          const TextField(decoration: InputDecoration(labelText: 'Phone')),
          ElevatedButton(onPressed: null, child: const Text('Save')),
          const Chip(label: Text('Open')),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        onTap: (_) {},
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.task), label: 'Tasks'),
        ],
      ),
    );
  }
}
