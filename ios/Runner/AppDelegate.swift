import ARKit
import Flutter
import UIKit

private class ARPoseStreamHandler: NSObject, FlutterStreamHandler {
  var eventSink: FlutterEventSink?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  private var arSession: ARSession?
  private var arTimer: Timer?
  private let arStreamHandler = ARPoseStreamHandler()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "URWalkingARPlugin") else {
      return
    }
    let messenger = registrar.messenger()

    FlutterEventChannel(
      name: "com.example.urwalking_sensor_host/arpose",
      binaryMessenger: messenger
    ).setStreamHandler(arStreamHandler)

    FlutterMethodChannel(
      name: "com.example.urwalking_sensor_host/camera",
      binaryMessenger: messenger
    ).setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "startArPose":
        self?.startArPose(result: result)
      case "stopArPose":
        self?.stopArPose(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func startArPose(result: @escaping FlutterResult) {
    guard ARWorldTrackingConfiguration.isSupported else {
      result(FlutterError(code: "NOT_SUPPORTED", message: "ARKit not supported on this device", details: nil))
      return
    }
    let session = ARSession()
    let config = ARWorldTrackingConfiguration()
    config.worldAlignment = .gravity
    session.run(config)
    arSession = session

    arTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
      self?.sendArPoseUpdate()
    }
    result(nil)
  }

  private func stopArPose(result: @escaping FlutterResult) {
    arTimer?.invalidate()
    arTimer = nil
    arSession?.pause()
    arSession = nil
    result(nil)
  }

  private func sendArPoseUpdate() {
    guard let frame = arSession?.currentFrame else { return }

    let t = frame.camera.transform
    let tx = Double(t.columns.3.x)
    let ty = Double(t.columns.3.y)
    let tz = Double(t.columns.3.z)

    let rot = simd_float3x3(
      t.columns.0.xyz,
      t.columns.1.xyz,
      t.columns.2.xyz
    )
    let q = simd_quatf(rot)

    let trackingState: String
    switch frame.camera.trackingState {
    case .normal:
      trackingState = "TRACKING"
    case .limited:
      trackingState = "LIMITED"
    case .notAvailable:
      trackingState = "NOT_AVAILABLE"
    @unknown default:
      trackingState = "UNKNOWN"
    }

    let data: [String: Any] = [
      "tx": tx,
      "ty": ty,
      "tz": tz,
      "qx": Double(q.imag.x),
      "qy": Double(q.imag.y),
      "qz": Double(q.imag.z),
      "qw": Double(q.real),
      "tracking": trackingState,
    ]

    DispatchQueue.main.async { [weak self] in
      self?.arStreamHandler.eventSink?(data)
    }
  }
}
