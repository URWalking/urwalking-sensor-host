import "package:sensors_plus/sensors_plus.dart";
import "package:urwalking_sensors/urwalking_sensors.dart";

/// Base class for the motion and environment sensors provided by
/// `sensors_plus`.
abstract class _SensorsPlusSensor extends StreamSensor {
  _SensorsPlusSensor({super.clock, Duration? samplingPeriod})
    : samplingPeriod = samplingPeriod ?? SensorInterval.gameInterval;

  /// How often the platform should deliver readings. This is a hint: the
  /// platform may deliver them faster or slower.
  final Duration samplingPeriod;

  SensorSample sample(Map<String, Object?> values) =>
      SensorSample(sensorId: id, timestamp: clock.now(), values: values);
}

/// Acceleration including gravity, in m/s².
///
/// Fields: `acc_x`, `acc_y`, `acc_z`.
class AccelerometerSensor extends _SensorsPlusSensor {
  /// Creates an accelerometer sensor.
  AccelerometerSensor({super.clock, super.samplingPeriod});

  @override
  String get id => "accelerometer";

  @override
  Stream<SensorSample> openSource() =>
      accelerometerEventStream(samplingPeriod: samplingPeriod).map(
        (AccelerometerEvent event) => sample(<String, Object?>{
          "acc_x": event.x,
          "acc_y": event.y,
          "acc_z": event.z,
        }),
      );
}

/// Rotation rate, in rad/s.
///
/// Fields: `gyro_x`, `gyro_y`, `gyro_z`.
class GyroscopeSensor extends _SensorsPlusSensor {
  /// Creates a gyroscope sensor.
  GyroscopeSensor({super.clock, super.samplingPeriod});

  @override
  String get id => "gyroscope";

  @override
  Stream<SensorSample> openSource() =>
      gyroscopeEventStream(samplingPeriod: samplingPeriod).map(
        (GyroscopeEvent event) => sample(<String, Object?>{
          "gyro_x": event.x,
          "gyro_y": event.y,
          "gyro_z": event.z,
        }),
      );
}

/// Magnetic field strength, in µT.
///
/// Fields: `mag_x`, `mag_y`, `mag_z`.
class MagnetometerSensor extends _SensorsPlusSensor {
  /// Creates a magnetometer sensor.
  MagnetometerSensor({super.clock, super.samplingPeriod});

  @override
  String get id => "magnetometer";

  @override
  Stream<SensorSample> openSource() =>
      magnetometerEventStream(samplingPeriod: samplingPeriod).map(
        (MagnetometerEvent event) => sample(<String, Object?>{
          "mag_x": event.x,
          "mag_y": event.y,
          "mag_z": event.z,
        }),
      );
}

/// Air pressure, in hPa.
///
/// Fields: `bar`.
class BarometerSensor extends _SensorsPlusSensor {
  /// Creates a barometer sensor.
  BarometerSensor({super.clock, super.samplingPeriod});

  @override
  String get id => "barometer";

  @override
  Stream<SensorSample> openSource() =>
      barometerEventStream(samplingPeriod: samplingPeriod).map(
        (BarometerEvent event) =>
            sample(<String, Object?>{"bar": event.pressure}),
      );
}
