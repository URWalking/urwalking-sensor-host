import "package:urwalking_sensors/src/core/sample_sink.dart";
import "package:urwalking_sensors/src/core/sensor_sample.dart";

/// Keeps all samples in memory. Useful for tests and short recordings that
/// are processed in the app itself.
class MemorySink extends SampleSink {
  final List<SensorSample> _samples = <SensorSample>[];

  /// All samples added so far, in arrival order.
  List<SensorSample> get samples => List<SensorSample>.unmodifiable(_samples);

  /// The samples of the sensor with id [sensorId], in arrival order.
  List<SensorSample> samplesOf(String sensorId) => <SensorSample>[
    for (SensorSample sample in _samples)
      if (sample.sensorId == sensorId) sample,
  ];

  /// Removes all stored samples.
  void clear() => _samples.clear();

  @override
  void add(SensorSample sample) => _samples.add(sample);

  @override
  Future<void> close() async {}
}
