import "dart:async";

import "package:flutter/foundation.dart";
import "package:urwalking_sensors/src/core/sensor_clock.dart";
import "package:urwalking_sensors/src/core/sensor_sample.dart";

/// A source of [SensorSample]s.
///
/// To add a custom sensor, extend [StreamSensor] (recommended) or implement
/// this class directly.
abstract class Sensor {
  /// A unique, stable identifier such as `"accelerometer"`.
  ///
  /// It ends up in file names and column headers, so it should only contain
  /// lowercase letters, digits and underscores.
  String get id;

  /// The samples of this sensor.
  ///
  /// This is a broadcast stream: several listeners (e.g. a live display and a
  /// Recorder) can listen at the same time. The sensor is only active while
  /// at least one listener is subscribed.
  Stream<SensorSample> get samples;

  /// Whether this sensor can be used on the current device.
  ///
  /// This is best effort: some platforms only report a missing sensor as an
  /// error on [samples].
  Future<bool> isAvailable() async => true;

  /// Releases all resources. The sensor cannot be used afterwards.
  Future<void> dispose() async {}
}

/// Base class for sensors whose data comes from a stream.
///
/// Subclasses implement [openSource]. The source is opened when the first
/// listener subscribes to [samples] and closed when the last one cancels,
/// so an unused sensor costs no battery.
abstract class StreamSensor extends Sensor {
  /// Creates a sensor that timestamps its samples with [clock], or with
  /// [SensorClock.shared] if none is given.
  StreamSensor({SensorClock? clock}) : clock = clock ?? SensorClock.shared;

  /// The clock this sensor takes its timestamps from.
  final SensorClock clock;

  late final StreamController<SensorSample> _controller =
      StreamController<SensorSample>.broadcast(
        onListen: _openSource,
        onCancel: _closeSource,
      );
  StreamSubscription<SensorSample>? _source;

  @override
  Stream<SensorSample> get samples => _controller.stream;

  /// Opens the underlying data source and maps it to [SensorSample]s.
  ///
  /// Called whenever [samples] gets its first listener. Timestamps should be
  /// taken from [clock].
  @protected
  Stream<SensorSample> openSource();

  void _openSource() {
    _source = openSource().listen(
      _controller.add,
      onError: _controller.addError,
    );
  }

  Future<void> _closeSource() async {
    await _source?.cancel();
    _source = null;
  }

  @override
  Future<void> dispose() async {
    await _closeSource();
    await _controller.close();
  }
}
