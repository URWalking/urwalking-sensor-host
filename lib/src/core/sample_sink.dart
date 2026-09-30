import "package:urwalking_sensors/src/core/sensor_sample.dart";

/// A destination for recorded [SensorSample]s, such as a CSV file or a
/// network stream.
///
/// To send data somewhere new, implement this class and pass it to a
/// Recorder.
abstract class SampleSink {
  /// Prepares the sink, e.g. creates files or opens a connection.
  ///
  /// Called once before the first [add].
  Future<void> open() async {}

  /// Handles one sample. Must return quickly: it is called for every sample
  /// of every sensor, so slow work should be buffered.
  void add(SensorSample sample);

  /// Flushes all pending data and releases resources.
  Future<void> close();
}
