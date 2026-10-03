package buildahome.buildahome

import android.os.Build
import android.os.Bundle
import androidx.annotation.NonNull
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant

class MainActivity: FlutterActivity() {
  override fun onCreate(savedInstanceState: Bundle?) {
    // Match Flutter's edge-to-edge layout so the native splash and first
    // Flutter frame share the same vertical center (avoids a top jump).
    WindowCompat.setDecorFitsSystemWindows(window, false)

    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
      // Android 12+ otherwise animates the splash upward on dismiss.
      splashScreen.setOnExitAnimationListener { splashScreenView ->
        splashScreenView.remove()
      }
    }

    super.onCreate(savedInstanceState)
  }

  override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
    GeneratedPluginRegistrant.registerWith(flutterEngine);
  }
}
