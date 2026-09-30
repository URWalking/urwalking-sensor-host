import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // AR pose lives in the urwalking_sensors_camera plugin, registered here
  // together with all other plugins.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "UrwalkingSensorHostApp") else {
      return
    }
    // Mirrors the channel in the Android MainActivity. iOS has no shared
    // Downloads folder, so logs go to the app's Documents directory.
    FlutterMethodChannel(
      name: "com.example.urwalking_sensor_host/app",
      binaryMessenger: registrar.messenger()
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "getDownloadsPath":
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        result(documents?.path)
      case "setKeepScreenOn":
        let on = (call.arguments as? [String: Any])?["on"] as? Bool ?? false
        UIApplication.shared.isIdleTimerDisabled = on
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
