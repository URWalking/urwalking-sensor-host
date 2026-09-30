import "package:flutter_compass/flutter_compass.dart";
import "package:urwalking_sensors/urwalking_sensors.dart";

/// The device heading, fused by the OS from magnetometer and motion sensors.
///
/// Fields:
/// - `com`: heading in degrees clockwise from magnetic north, 0 to 360, or
///   `null` while the OS has no heading
/// - `com_accuracy`: estimated error in degrees (`null` if unknown)
class CompassSensor extends StreamSensor {
  /// Creates a compass sensor.
  CompassSensor({super.clock});

  @override
  String get id => "compass";

  @override
  Future<bool> isAvailable() async => FlutterCompass.events != null;

  @override
  Stream<SensorSample> openSource() {
    Stream<CompassEvent>? events = FlutterCompass.events;
    if (events == null) {
      return Stream<SensorSample>.error(
        UnsupportedError("This device has no compass."),
      );
    }
    return events.map(
      (CompassEvent event) => SensorSample(
        sensorId: id,
        timestamp: clock.now(),
        values: <String, Object?>{
          "com": event.heading == null ? null : event.heading! % 360,
          "com_accuracy": event.accuracy,
        },
      ),
    );
  }
}
