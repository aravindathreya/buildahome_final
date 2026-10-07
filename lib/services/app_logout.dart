import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../Skin2/loginPage.dart';
import '../app_navigator.dart';
import '../chat_v1/chat_v1_api.dart';
import '../chat_v1/chat_v1_project_summaries.dart';
import '../chat_v1/chat_v1_socket.dart';
import 'app_deep_link_service.dart';
import 'client_generation_service.dart';
import 'client_portal_service.dart';
import 'data_provider.dart';
import 'mobile_live_test_storage.dart';
import 'mobile_bottom_nav_service.dart';
import 'mobile_documents_service.dart';
import 'mobile_more_menu_service.dart';
import 'mobile_quick_actions_service.dart';
import 'notification_service.dart';
import 'push/push_notification_service.dart';
import 'screen_capture_policy.dart';
import 'profile_picture_service.dart';
import 'staff_location_tracker.dart';
import '../widgets/client_home_tour.dart';

/// Single logout path for client + staff so we never leave a half-cleared
/// session that auto-opens another user's home / profile-pic prompt.
class AppLogout {
  AppLogout._();

  /// Instant in-memory wipe so the old UI cannot keep rendering user data.
  static void _clearInMemoryNow() {
    ScreenCapturePolicy.protect();
    try {
      StaffLocationTracker.instance.stop();
    } catch (_) {}
    try {
      ChatV1Socket.instance.disconnect();
    } catch (_) {}
    DataProvider().clearData();
    ChatProjectSummaryStore.instance.clear();
    MobileQuickActionsService.instance.clearMemory();
    MobileMoreMenuService.instance.clearMemory();
    MobileBottomNavService.instance.clearMemory();
    MobileDocumentsService.instance.clearMemory();
    AppDeepLinkService.instance.onLoggedOut();
    ProfilePictureService.onLoggedOut();
    LoginScreenNew.preferFreshLogin = true;
  }

  /// Wipe persisted auth state (safe to run after login is already showing).
  static Future<void> clearLocalSession() async {
    _clearInMemoryNow();
    try {
      await PushNotificationService.instance.unbindCurrentUser();
    } catch (e) {
      print('[AppLogout] FCM unregister failed: $e');
    }

    try {
      await ClientGenerationService.instance.clear();
    } catch (e) {
      print('[AppLogout] ClientGenerationService.clear failed: $e');
    }

    try {
      await ClientPortalService().clearSession();
    } catch (e) {
      print('[AppLogout] ClientPortalService.clearSession failed: $e');
    }

    try {
      await ChatV1Api.instance.clearSession();
    } catch (e) {
      print('[AppLogout] ChatV1Api.clearSession failed: $e');
    }

    try {
      await NotificationService.instance.clear();
    } catch (e) {
      print('[AppLogout] NotificationService.clear failed: $e');
    }

    try {
      await ProfilePictureService.clearStored();
    } catch (_) {
      ProfilePictureService.onLoggedOut();
    }

    Map<String, bool> preservedTourFlags = const {};
    Map<String, int> preservedSkipCounts = const {};
    String? preservedDeviceId;
    try {
      final preferences = await SharedPreferences.getInstance();
      preservedDeviceId = preferences.getString('fcm_device_id');
      // Keep "Welcome to your home" completion across logout/login.
      preservedTourFlags = {
        for (final key in preferences.getKeys())
          if (ClientHomeTour.isTourPrefKey(key) &&
              preferences.getBool(key) == true)
            key: true,
      };
      // Keep profile-pic skip counters across logout/login.
      preservedSkipCounts = {
        for (final key in preferences.getKeys())
          if (ProfilePictureService.isSkipPrefKey(key))
            key: preferences.getInt(key) ?? 0,
      };
      await preferences.clear();
      if (preservedDeviceId != null && preservedDeviceId.trim().isNotEmpty) {
        await preferences.setString('fcm_device_id', preservedDeviceId.trim());
      }
      await ClientHomeTour.restorePreservedFlags(preservedTourFlags);
      await ProfilePictureService.restorePreservedSkipCounts(
        preservedSkipCounts,
      );
    } catch (e) {
      print('[AppLogout] SharedPreferences.clear failed: $e');
    }

    try {
      await MobileLiveTestCredentials.clearLocal();
    } catch (e) {
      print('[AppLogout] MobileLiveTestCredentials.clearLocal failed: $e');
    }

    // Keep this true until LoginScreenNew consumes it.
    LoginScreenNew.preferFreshLogin = true;
  }

  static Route<void> _loginRoute() {
    return PageRouteBuilder<void>(
      pageBuilder: (context, animation, secondaryAnimation) => LoginScreenNew(),
      // Instant swap — avoids a 1-frame flash of the previous home / profile UI.
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      opaque: true,
    );
  }

  /// Jump to login immediately, then finish clearing session in the background.
  static Future<void> logoutAndGoToLogin({BuildContext? context}) async {
    _clearInMemoryNow();

    final navigator = globalNavigatorKey.currentState;
    if (navigator != null) {
      navigator.pushAndRemoveUntil(_loginRoute(), (route) => false);
    } else if (context != null && context.mounted) {
      Navigator.of(context, rootNavigator: true)
          .pushAndRemoveUntil(_loginRoute(), (route) => false);
    }

    _dismissDialogsAboveLogin();
    await clearLocalSession();
    // A startup prompt may have been awaiting and pushed onto the login
    // route after the first navigation. Drop it once the session is gone.
    _dismissDialogsAboveLogin();
  }

  /// Login is the only route that should remain. Startup dialogs use the
  /// root navigator and can land on top of it if they resume after logout.
  static void _dismissDialogsAboveLogin() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ProfilePictureService.promptsSuppressed) return;
      final nav = globalNavigatorKey.currentState;
      if (nav == null) return;
      nav.popUntil((route) => route.isFirst);
    });
  }
}
