import "package:flutter/foundation.dart";

/// A single reading of one sensor.
///
/// Every sensor, built-in or user-defined, reports its data in this format,
/// so sinks and processing steps can handle all sensors the same way.
@immutable
class SensorSample {
  /// Creates a sample of the sensor with id [sensorId].
  const SensorSample({
    required this.sensorId,
    required this.timestamp,
    required this.values,
  });

  /// The `Sensor.id` of the sensor that produced this sample.
  final String sensorId;

  /// When the sample was taken, on the sensor's SensorClock.
  final DateTime timestamp;

  /// The measured values by field name, e.g. `{"acc_x": 0.1, ...}`.
  ///
  /// Values are [num], [String], [bool] or `null`. Every sample of a sensor
  /// should contain the same field names in the same order, because sinks
  /// such as the CSV sink derive their columns from the first sample.
  final Map<String, Object?> values;

  @override
  String toString() => "SensorSample($sensorId, $timestamp, $values)";
}
