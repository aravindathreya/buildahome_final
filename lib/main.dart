// Built in packages
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'Skin2/loginPage.dart';
import 'UserDashboard.dart';
import 'app_navigator.dart';
import 'app_theme.dart';
import 'providers/theme_provider.dart';
import 'services/session_manager.dart';

export 'app_navigator.dart';

final UserDashboardNavigatorObserver globalNavigatorObserver =
    UserDashboardNavigatorObserver();

void main() => runApp(App());

class App extends StatefulWidget {
  final fontName = 'Mulish-Regular';

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SessionManager.instance.validateSessionIfLoggedIn(force: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SessionManager.instance.validateSessionIfLoggedIn();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';

    return ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: appTitle,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.getLightTheme(),
            darkTheme: AppTheme.getDarkTheme(),
            themeMode:
                themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            navigatorKey: globalNavigatorKey,
            scaffoldMessengerKey: globalScaffoldMessengerKey,
            navigatorObservers: [globalNavigatorObserver],
            home: Scaffold(
              body: LoginScreenNew(),
            ),
          );
        },
      ),
    );
  }
}
