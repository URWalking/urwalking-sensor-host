import "package:pedometer/pedometer.dart";
import "package:urwalking_sensors/urwalking_sensors.dart";

/// Steps counted by the device's step counter.
///
/// Fields:
/// - `step_total`: steps since the last device reboot (as reported by the OS)
/// - `step_session`: steps since the sensor started or [resetSession] was
///   last called
///
/// Requires the activity recognition permission on Android
/// (`ACTIVITY_RECOGNITION`) and motion usage (`NSMotionUsageDescription`) on
/// iOS. The app has to request it before listening.
class StepCountSensor extends StreamSensor {
  /// Creates a step count sensor.
  StepCountSensor({super.clock});

  int? _sessionBaseline;
  int? _lastTotal;

  @override
  String get id => "pedometer_steps";

  /// Starts counting `step_session` from zero again.
  void resetSession() => _sessionBaseline = _lastTotal;

  @override
  Stream<SensorSample> openSource() {
    _sessionBaseline = null;
    return Pedometer.stepCountStream.map((StepCount event) {
      int total = event.steps;
      _lastTotal = total;
      int baseline = _sessionBaseline ??= total;
      // The OS counter resets on reboot, which would make the session
      // count negative.
      int session = total < baseline ? 0 : total - baseline;
      return SensorSample(
        sensorId: id,
        timestamp: clock.now(),
        values: <String, Object?>{"step_total": total, "step_session": session},
      );
    });
  }
}

/// Whether the user is currently walking, as detected by the OS.
///
/// Fields: `pedometer_status` (`"walking"`, `"stopped"` or `"unknown"`).
///
/// Needs the same permissions as [StepCountSensor].
class PedestrianStatusSensor extends StreamSensor {
  /// Creates a pedestrian status sensor.
  PedestrianStatusSensor({super.clock});

  @override
  String get id => "pedometer_status";

  @override
  Stream<SensorSample> openSource() => Pedometer.pedestrianStatusStream.map(
    (PedestrianStatus event) => SensorSample(
      sensorId: id,
      timestamp: clock.now(),
      values: <String, Object?>{"pedometer_status": event.status},
    ),
  );
}
