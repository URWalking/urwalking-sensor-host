import ARKit
import CoreImage
import Flutter
import UIKit

/// ARKit pose tracking and camera frame capture.
///
/// ARKit owns the camera while its session runs, so frames are taken from
/// the session itself instead of a separate capture pipeline, which could
/// not open the camera at the same time. This mirrors Android, where the
/// camera is shared with ARCore: `startArPose` reports the shared camera id
/// and `startFastCapture` writes that camera's frames as 640×480 JPEGs.
public class UrwalkingCameraPlugin: NSObject, FlutterPlugin, FlutterStreamHandler, ARSessionDelegate {
  /// The only camera on iOS: the back camera driven by the AR session.
  private static let arCameraId = "back"
  private static let frameWidth: CGFloat = 640
  private static let frameHeight: CGFloat = 480
  /// ARKit delivers 60 fps; frames closer together than this are skipped.
  private static let minFrameInterval: TimeInterval = 1.0 / 30.0

  private var arSession: ARSession?
  private var arTimer: Timer?
  private var eventSink: FlutterEventSink?

  /// ARKit calls the session delegate on this queue.
  private let frameQueue = DispatchQueue(label: "urwalking_sensors_camera.frames")
  /// Encodes and writes frames, so ARKit's queue is never blocked.
  private let encodeQueue = DispatchQueue(label: "urwalking_sensors_camera.encode", qos: .userInitiated)
  private let ciContext = CIContext(options: [.cacheIntermediates: false])

  /// The running capture. Only touched on `encodeQueue`.
  private var capture: FrameWriter?
  /// Whether frames should be captured, and when the last one was taken.
  /// Only touched on `frameQueue`.
  private var isCapturing = false
  private var isEncoding = false
  private var lastFrameTime: TimeInterval = 0

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
    let arguments = call.arguments as? [String: Any]
    switch call.method {
    case "startArPose":
      startArPose(result: result)
    case "stopArPose":
      stopFastCapture { [weak self] in
        self?.stopArPose()
        result(nil)
      }
    case "listCameras":
      listCameras(result: result)
    case "openCamera":
      // The AR camera is opened by startArPose; there is no other camera.
      if arguments?["cameraId"] as? String == Self.arCameraId, arSession != nil {
        result(0)
      } else {
        result(FlutterError(
          code: "UNSUPPORTED",
          message: "On iOS, frames are only captured from the AR session's camera",
          details: nil
        ))
      }
    case "startFastCapture":
      startFastCapture(arguments: arguments, result: result)
    case "stopFastCapture", "closeCamera":
      stopFastCapture { result(nil) }
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
    stopFastCapture {}
    stopArPose()
  }

  // MARK: - Cameras

  private func listCameras(result: @escaping FlutterResult) {
    var cameras: [[String: Any]] = []
    if ARWorldTrackingConfiguration.isSupported {
      cameras.append([
        "id": Self.arCameraId,
        "name": "Camera \(Self.arCameraId) (Back, ARKit)",
        "facing": 1, // CameraFacing.back, Android's LENS_FACING_BACK
        "isLogical": false,
      ])
    }
    result(["cameras": cameras, "concurrentSets": []])
  }

  private func startFastCapture(arguments: [String: Any]?, result: @escaping FlutterResult) {
    guard let cameraId = arguments?["cameraId"] as? String else {
      result(FlutterError(code: "INVALID_ARG", message: "Missing cameraId", details: nil))
      return
    }
    guard let outputDir = arguments?["outputDir"] as? String else {
      result(FlutterError(code: "INVALID_ARG", message: "Missing outputDir", details: nil))
      return
    }
    guard cameraId == Self.arCameraId, arSession != nil else {
      result(FlutterError(
        code: "NOT_READY",
        message: "Frames can only be captured while the AR session runs",
        details: nil
      ))
      return
    }

    encodeQueue.async { [weak self] in
      guard let self else { return }
      do {
        self.capture?.close()
        self.capture = try FrameWriter(directory: URL(fileURLWithPath: outputDir))
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "CAPTURE_ERR", message: error.localizedDescription, details: nil))
        }
        return
      }
      self.frameQueue.async {
        self.isCapturing = true
        self.lastFrameTime = 0
        DispatchQueue.main.async { result(nil) }
      }
    }
  }

  /// Stops taking frames, waits until the ones in flight are written, then
  /// closes the frame log and calls [completion] on the main queue.
  private func stopFastCapture(completion: @escaping () -> Void) {
    frameQueue.async { [weak self] in
      guard let self else { return }
      self.isCapturing = false
      // Anything already handed to encodeQueue runs before this block.
      self.encodeQueue.async {
        self.capture?.close()
        self.capture = nil
        DispatchQueue.main.async(execute: completion)
      }
    }
  }

  // MARK: - AR session

  private func startArPose(result: @escaping FlutterResult) {
    guard ARWorldTrackingConfiguration.isSupported else {
      result(FlutterError(code: "NOT_SUPPORTED", message: "ARKit not supported on this device", details: nil))
      return
    }
    if arSession == nil {
      let session = ARSession()
      session.delegate = self
      session.delegateQueue = frameQueue
      let config = ARWorldTrackingConfiguration()
      config.worldAlignment = .gravity
      session.run(config)
      arSession = session

      arTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
        self?.sendArPoseUpdate()
      }
    }
    // Reported so FrameCapture records from the AR session's camera.
    result(Self.arCameraId)
  }

  private func stopArPose() {
    arTimer?.invalidate()
    arTimer = nil
    arSession?.pause()
    arSession = nil
  }

  /// Called by ARKit on `frameQueue` for every camera frame.
  public func session(_ session: ARSession, didUpdate frame: ARFrame) {
    guard isCapturing, !isEncoding else { return }
    let now = Date().timeIntervalSince1970
    guard now - lastFrameTime >= Self.minFrameInterval else { return }
    lastFrameTime = now
    isEncoding = true

    // Only the pixel buffer is kept, not the ARFrame: holding on to frames
    // starves ARKit of buffers and stalls tracking.
    let pixelBuffer = frame.capturedImage
    let timestampMs = Int64((now * 1000).rounded())
    encodeQueue.async { [weak self] in
      guard let self else { return }
      if let capture = self.capture, let jpeg = self.encodeJpeg(pixelBuffer) {
        capture.write(jpeg: jpeg, timestampMs: timestampMs)
      }
      self.frameQueue.async { self.isEncoding = false }
    }
  }

  /// Scales the camera image (4:3, e.g. 1920×1440) to 640×480 and encodes
  /// it. Like on Android, the image stays in the sensor's landscape
  /// orientation.
  private func encodeJpeg(_ pixelBuffer: CVPixelBuffer) -> Data? {
    let image = CIImage(cvPixelBuffer: pixelBuffer)
    let scaled = image.transformed(by: CGAffineTransform(
      scaleX: Self.frameWidth / image.extent.width,
      y: Self.frameHeight / image.extent.height
    ))
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
    return ciContext.jpegRepresentation(
      of: scaled,
      colorSpace: colorSpace,
      options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.8]
    )
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

/// Writes frames as `frame_<ms>.jpg` into a directory and logs each one in
/// `image_timestamps.csv` (`phone_ts_ms,filename`), the same files the
/// Android side writes.
private final class FrameWriter {
  private let directory: URL
  private let log: FileHandle

  init(directory: URL) throws {
    self.directory = directory
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let logURL = directory.appendingPathComponent("image_timestamps.csv")
    try Data("phone_ts_ms,filename\n".utf8).write(to: logURL)
    log = try FileHandle(forWritingTo: logURL)
    log.seekToEndOfFile()
  }

  func write(jpeg: Data, timestampMs: Int64) {
    let filename = "frame_\(timestampMs).jpg"
    do {
      try jpeg.write(to: directory.appendingPathComponent(filename))
      log.write(Data("\(timestampMs),\(filename)\n".utf8))
    } catch {
      NSLog("[urwalking_sensors_camera] Writing \(filename) failed: \(error)")
    }
  }

  func close() {
    try? log.close()
  }
}

private extension simd_float4 {
  /// The first three components, e.g. a rotation column of a 4x4 transform.
  var xyz: simd_float3 { simd_float3(x, y, z) }
}
