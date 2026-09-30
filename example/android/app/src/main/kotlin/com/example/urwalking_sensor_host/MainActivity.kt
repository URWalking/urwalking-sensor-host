package com.example.urwalking_sensor_host

import android.os.Environment
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * App-specific platform calls. Camera capture and ARCore live in the
 * urwalking_sensors_camera plugin.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.urwalking_sensor_host/app")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDownloadsPath" -> {
                        result.success(
                            Environment.getExternalStoragePublicDirectory(
                                Environment.DIRECTORY_DOWNLOADS
                            ).absolutePath
                        )
                    }

                    "setKeepScreenOn" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        if (on) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        }
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
