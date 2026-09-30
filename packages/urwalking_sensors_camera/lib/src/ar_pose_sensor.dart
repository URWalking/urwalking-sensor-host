import "package:flutter/services.dart";
import "package:urwalking_sensors/urwalking_sensors.dart";
import "package:urwalking_sensors_camera/src/frame_capture.dart";

/// 6DOF device pose from ARCore (Android) or ARKit (iOS).
///
/// Call [startSession] before listening; samples only arrive while the AR
/// session runs.
///
/// Fields:
/// - `ar_tx`, `ar_ty`, `ar_tz`: position in m, relative to where the
///   session started
/// - `ar_qx`, `ar_qy`, `ar_qz`, `ar_qw`: orientation quaternion
/// - `ar_tracking`: tracking state, e.g. `TRACKING` or `PAUSED`
///
/// Requires the camera permission.
class ArPoseSensor extends StreamSensor {
  /// Creates the sensor.
  ArPoseSensor({super.clock});

  static const EventChannel _poseChannel = EventChannel(
    "urwalking_sensors_camera/arpose",
  );

  String? _sharedCameraId;

  @override
  String get id => "arpose";

  /// On Android, the camera ARCore opened and shares with FrameCapture
  /// (pass it to `FrameCapture.useCamera`). Null on iOS and before
  /// [startSession].
  String? get sharedCameraId => _sharedCameraId;

  /// Starts the AR session. Returns false if AR is not supported on this
  /// device or could not be started.
  Future<bool> startSession() async {
    try {
      _sharedCameraId = await cameraChannel.invokeMethod<String>("startArPose");
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Stops the AR session and releases the camera.
  Future<void> stopSession() async {
    _sharedCameraId = null;
    try {
      await cameraChannel.invokeMethod<void>("stopArPose");
    } on PlatformException {
      // The session was not running.
    } on MissingPluginException {
      // No native side on this platform.
    }
  }

  @override
  Stream<SensorSample> openSource() =>
      _poseChannel.receiveBroadcastStream().map((Object? data) {
        Map<Object?, Object?> pose = data! as Map<Object?, Object?>;
        double number(String key) => (pose[key]! as num).toDouble();
        return SensorSample(
          sensorId: id,
          timestamp: clock.now(),
          values: <String, Object?>{
            "ar_tx": number("tx"),
            "ar_ty": number("ty"),
            "ar_tz": number("tz"),
            "ar_qx": number("qx"),
            "ar_qy": number("qy"),
            "ar_qz": number("qz"),
            "ar_qw": number("qw"),
            "ar_tracking": pose["tracking"],
          },
        );
      });
}
