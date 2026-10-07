package buildahome.buildahome

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.view.WindowManager
import androidx.annotation.NonNull
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity: FlutterActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    // Match Flutter's edge-to-edge layout so the native splash and first
    // Flutter frame share the same vertical center (avoids a top jump).
    WindowCompat.setDecorFitsSystemWindows(window, false)

    // Block screenshots / screen recording / recents preview for all views.
    window.setFlags(
      WindowManager.LayoutParams.FLAG_SECURE,
      WindowManager.LayoutParams.FLAG_SECURE
    )

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      // Android 12+ otherwise animates the splash upward on dismiss.
      splashScreen.setOnExitAnimationListener { splashScreenView ->
        splashScreenView.remove()
      }
    }

    super.onCreate(savedInstanceState)
  }

  override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    MethodChannel(
      flutterEngine.dartExecutor.binaryMessenger,
      "buildahome/notification_settings"
    ).setMethodCallHandler { call, result ->
      when (call.method) {
        "enabled" -> {
          val enabled = androidx.core.app.NotificationManagerCompat
            .from(this)
            .areNotificationsEnabled()
          result.success(enabled)
        }
        "open" -> {
          try {
            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
              putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
              putExtra("app_package", packageName)
              putExtra("app_uid", applicationInfo.uid)
              addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            result.success(true)
          } catch (error: Exception) {
            val fallback = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
              data = android.net.Uri.fromParts("package", packageName, null)
              addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(fallback)
            result.success(true)
          }
        }
        else -> result.notImplemented()
      }
    }
  }
}
