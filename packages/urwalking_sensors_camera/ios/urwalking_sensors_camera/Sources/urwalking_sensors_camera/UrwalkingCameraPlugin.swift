import ARKit
import Flutter
import UIKit

/// ARKit pose tracking. Camera frame capture is not implemented on iOS yet:
/// `listCameras` reports no cameras and the capture methods fail with
/// `UNSUPPORTED`.
public class UrwalkingCameraPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private var arSession: ARSession?
  private var arTimer: Timer?
  private var eventSink: FlutterEventSink?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = UrwalkingCameraPlugin()
    let methods = FlutterMethodChannel(
      name: "urwalking_sensors_camera/camera",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: methods)
    FlutterEventChannel(
      name: "urwalking_sensors_camera/arpose",
      binaryMessenger: registrar.messenger()
    ).setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "startArPose":
      startArPose(result: result)
    case "stopArPose":
      stopArPose()
      result(nil)
    case "listCameras":
      result(["cameras": [], "concurrentSets": []])
    case "closeCamera":
      result(nil)
    case "openCamera", "startFastCapture", "stopFastCapture":
      result(FlutterError(
        code: "UNSUPPORTED",
        message: "Camera frame capture is not implemented on iOS yet",
        details: nil
      ))
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    stopArPose()
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
    // ARKit does not share its camera with a capture pipeline, so there is
    // no camera id to report.
    result(nil)
  }

  private func stopArPose() {
    arTimer?.invalidate()
    arTimer = nil
    arSession?.pause()
    arSession = nil
  }

  private func sendArPoseUpdate() {
    guard let frame = arSession?.currentFrame else { return }

    let t = frame.camera.transform
    let rotation = simd_float3x3(t.columns.0.xyz, t.columns.1.xyz, t.columns.2.xyz)
    let q = simd_quatf(rotation)

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
      "tx": Double(t.columns.3.x),
      "ty": Double(t.columns.3.y),
      "tz": Double(t.columns.3.z),
      "qx": Double(q.imag.x),
      "qy": Double(q.imag.y),
      "qz": Double(q.imag.z),
      "qw": Double(q.real),
      "tracking": trackingState,
    ]

    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(data)
    }
  }
}

private extension simd_float4 {
  /// The first three components, e.g. a rotation column of a 4x4 transform.
  var xyz: simd_float3 { simd_float3(x, y, z) }
}
