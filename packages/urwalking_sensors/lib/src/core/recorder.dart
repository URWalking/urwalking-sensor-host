import "dart:async";

import "package:urwalking_sensors/src/core/sample_sink.dart";
import "package:urwalking_sensors/src/core/sensor.dart";
import "package:urwalking_sensors/src/core/sensor_sample.dart";

/// An error that a sensor reported while recording.
class SensorError {
  /// Creates an error reported by the sensor with id [sensorId].
  const SensorError(this.sensorId, this.error, this.stackTrace);

  /// The [Sensor.id] of the sensor that failed.
  final String sensorId;

  /// The error the sensor reported.
  final Object error;

  /// Where the error happened.
  final StackTrace stackTrace;

  @override
  String toString() => "SensorError($sensorId): $error";
}

/// Records samples from a set of [sensors] into a set of [sinks].
///
/// ```dart
/// Recorder recorder = Recorder(
///   sensors: <Sensor>[AccelerometerSensor(), GyroscopeSensor()],
///   sinks: <SampleSink>[CsvSink(directory)],
/// );
/// await recorder.start();
/// // ...
/// await recorder.stop();
/// ```
class Recorder {
  /// Creates a recorder. Nothing happens until [start] is called.
  Recorder({required this.sensors, required this.sinks});

  /// The sensors whose samples are recorded.
  final List<Sensor> sensors;

  /// Where the samples go. Every sample is passed to every sink.
  final List<SampleSink> sinks;

  final List<StreamSubscription<SensorSample>> _subscriptions =
      <StreamSubscription<SensorSample>>[];
  final StreamController<SensorError> _errors =
      StreamController<SensorError>.broadcast();
  bool _isRecording = false;

  /// Whether a recording is in progress.
  bool get isRecording => _isRecording;

  /// Errors reported by the sensors while recording. A failing sensor does
  /// not stop the recording of the other sensors.
  Stream<SensorError> get errors => _errors.stream;

  /// Opens all sinks and starts recording.
  Future<void> start() async {
    if (_isRecording) {
      throw StateError("Recorder is already recording.");
    }
    _isRecording = true;
    for (SampleSink sink in sinks) {
      await sink.open();
    }
    for (Sensor sensor in sensors) {
      _subscriptions.add(
        sensor.samples.listen(
          _dispatch,
          onError: (Object error, StackTrace stackTrace) =>
              _errors.add(SensorError(sensor.id, error, stackTrace)),
        ),
      );
    }
  }

  /// Stops recording and closes all sinks.
  Future<void> stop() async {
    if (!_isRecording) {
      return;
    }
    for (StreamSubscription<SensorSample> subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    for (SampleSink sink in sinks) {
      await sink.close();
    }
    _isRecording = false;
  }

  /// Stops recording and releases all resources.
  Future<void> dispose() async {
    await stop();
    await _errors.close();
  }

  void _dispatch(SensorSample sample) {
    for (SampleSink sink in sinks) {
      sink.add(sample);
    }
  }
}
