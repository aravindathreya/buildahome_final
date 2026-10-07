/// When notifications are off, the dashboard offers a direct jump to this
/// app's notification settings so the user can turn them on.
enum NotificationEnableAction { requestPermission, openSettings }

class NotificationPermissionPolicy {
  static bool bannerVisible({required bool permissionEnabled}) =>
      !permissionEnabled;

  static NotificationEnableAction enableAction() =>
      NotificationEnableAction.openSettings;

  static bool isEnabledStatusName(String statusName) {
    final name = statusName.toLowerCase();
    return name.contains('granted') ||
        name.contains('limited') ||
        name.contains('provisional');
  }

  /// App open should show the system Allow/Don't allow dialog while Android
  /// or iOS will still present it. A permanent denial cannot show that dialog.
  static bool shouldRequestSystemDialog({
    required String permissionStatusName,
  }) {
    final name = permissionStatusName.toLowerCase();
    if (isEnabledStatusName(name)) return false;
    if (name.contains('permanent') || name.contains('restricted')) {
      return false;
    }
    return true;
  }

  /// A request that returns immediately without a grant never showed a dialog
  /// (activity not ready, or the OS skipped it). A real dialog waits on the user.
  static bool systemDialogWasPresented({
    required bool granted,
    required int elapsedMilliseconds,
  }) {
    if (granted) return true;
    return elapsedMilliseconds >= 200;
  }
}
