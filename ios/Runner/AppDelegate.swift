import UIKit
import UserNotifications
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "buildahome/notification_settings",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        if call.method == "open" {
          self.openNotificationSettings(result: result)
        } else if call.method == "enabled" {
          UNUserNotificationCenter.current().getNotificationSettings { settings in
            let on = settings.authorizationStatus == .authorized
              || settings.authorizationStatus == .provisional
            DispatchQueue.main.async {
              result(on)
            }
          }
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return launched
  }

  private func openNotificationSettings(result: @escaping FlutterResult) {
    let urlString: String
    if #available(iOS 16.0, *) {
      urlString = UIApplication.openNotificationSettingsURLString
    } else {
      urlString = UIApplication.openSettingsURLString
    }
    guard let url = URL(string: urlString) else {
      result(false)
      return
    }
    UIApplication.shared.open(url, options: [:]) { opened in
      result(opened)
    }
  }
}
