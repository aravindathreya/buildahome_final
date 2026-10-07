// Built in packages
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'Skin2/loginPage.dart';
import 'UserDashboard.dart';
import 'app_navigator.dart';
import 'app_scroll_behavior.dart';
import 'app_theme.dart';
import 'services/app_deep_link_service.dart';
import 'services/push/notification_permission_controller.dart';
import 'services/push/push_notification_service.dart';
import 'services/screen_capture_policy.dart';
import 'services/session_manager.dart';
import 'services/theme_service.dart';
import 'widgets/theme_tree_refresher.dart';

export 'app_navigator.dart';

final UserDashboardNavigatorObserver globalNavigatorObserver =
    UserDashboardNavigatorObserver();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GestureBinding.instance.resamplingEnabled = true;
  await ScreenCapturePolicy.apply();
  await PushNotificationService.instance.initialize();
  runApp(App());
}

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
    ThemeService.instance.load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        NotificationPermissionController.instance.promptOnAppOpen(),
      );
      // Let Home start its own authenticated calls first. This probe only
      // logs out when the server explicitly says the token was replaced.
      Future<void>.delayed(const Duration(seconds: 2), () {
        SessionManager.instance.validateSessionIfLoggedIn(force: true);
      });
      AppDeepLinkService.instance.start();
    });
  }

  @override
  void dispose() {
    AppDeepLinkService.instance.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SessionManager.instance.validateSessionIfLoggedIn();
      unawaited(NotificationPermissionController.instance.promptOnAppOpen());
      NotificationPermissionController.instance.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';

    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeService.instance.modeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: appTitle,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.getLightTheme(),
          darkTheme: AppTheme.getDarkTheme(),
          themeMode: themeMode,
          // Snap between appearances. Animating the theme interpolates text
          // styles and throws when light and dark styles don't match.
          themeAnimationDuration: Duration.zero,
          builder: (context, child) {
            return ThemeTreeRefresher(
              child: child ?? const SizedBox.shrink(),
            );
          },
          scrollBehavior: const AppScrollBehavior(),
          navigatorKey: globalNavigatorKey,
          scaffoldMessengerKey: globalScaffoldMessengerKey,
          navigatorObservers: [globalNavigatorObserver],
          home: LoginScreenNew(),
        );
      },
    );
  }
}
