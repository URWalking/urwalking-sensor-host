/// Read, record and export sensor data on Android and iOS.
///
/// The building blocks are:
/// - [Sensor]: a source of [SensorSample]s. Extend [StreamSensor] to add your
///   own sensor.
/// - [SampleSink]: a destination for samples, e.g. [CsvSink].
/// - [Recorder]: connects sensors to sinks for the duration of a recording.
library;

import "package:urwalking_sensors/src/core/recorder.dart";
import "package:urwalking_sensors/src/core/sample_sink.dart";
import "package:urwalking_sensors/src/core/sensor.dart";
import "package:urwalking_sensors/src/core/sensor_sample.dart";
import "package:urwalking_sensors/src/sinks/csv_sink.dart";

export "src/core/recorder.dart";
export "src/core/sample_sink.dart";
export "src/core/sensor.dart";
export "src/core/sensor_clock.dart";
export "src/core/sensor_sample.dart";
export "src/processing/interpolation.dart";
export "src/sinks/csv_sink.dart";
export "src/sinks/memory_sink.dart";
