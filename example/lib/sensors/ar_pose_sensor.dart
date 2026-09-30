import "package:flutter/services.dart";
import "package:urwalking_sensors/urwalking_sensors.dart";

/// ARCore 6DOF device pose, implemented in this app's MainActivity.
///
/// This is an example of a custom sensor: it wraps an app-specific
/// EventChannel into the library's [StreamSensor] so it can be displayed and
/// recorded like any built-in sensor.
///
/// Fields: `ar_tx`, `ar_ty`, `ar_tz` (position in m), `ar_qx`, `ar_qy`,
/// `ar_qz`, `ar_qw` (orientation quaternion) and `ar_tracking` (ARCore's
/// tracking state).
class ArPoseSensor extends StreamSensor {
  /// Creates the sensor. Call [startSession] before listening.
  ArPoseSensor({super.clock});

  static const EventChannel _poseChannel = EventChannel(
    "com.example.urwalking_sensor_host/arpose",
  );
  static const MethodChannel _methodChannel = MethodChannel(
    "com.example.urwalking_sensor_host/camera",
  );

  @override
  String get id => "arpose";

  /// Starts the ARCore session and returns the id of the camera it shares
  /// with the native capture pipeline, or null if ARCore is not supported.
  Future<String?> startSession() async {
    try {
      return await _methodChannel.invokeMethod<String>("startArPose");
    } on PlatformException {
      return null;
    }
  }

  /// Stops the ARCore session.
  Future<void> stopSession() async {
    try {
      await _methodChannel.invokeMethod<void>("stopArPose");
    } on PlatformException {
      // The session was not running.
    }
  }

  @override
  Stream<SensorSample> openSource() =>
      _poseChannel.receiveBroadcastStream().map((Object? data) {
        Map<String, Object?> pose = Map<String, Object?>.from(
          data! as Map<Object?, Object?>,
        );
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
