import "dart:async";

import "package:flutter/foundation.dart";
import "package:urwalking_sensors/urwalking_sensors.dart";

/// Holds the latest sample of a sensor for display.
///
/// Listening keeps the sensor active, so only [attach] sensors that should
/// be running.
class LiveSample extends ValueNotifier<SensorSample?> {
  /// Creates an empty holder. Errors of the attached sensor go to [onError].
  LiveSample({this.onError}) : super(null);

  /// Called with every error the attached sensor reports.
  final void Function(Object error)? onError;

  StreamSubscription<SensorSample>? _subscription;

  /// Whether a sensor is attached.
  bool get isAttached => _subscription != null;

  /// Starts listening to [sensor], replacing any previously attached one.
  Future<void> attach(Sensor sensor) async {
    await detach();
    _subscription = sensor.samples.listen(handle, onError: _handleError);
  }

  /// Stops listening.
  Future<void> detach() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// Handles one sample of the attached sensor.
  @protected
  // Not a setter: subclasses override it to collect samples.
  // ignore: use_setters_to_change_properties
  void handle(SensorSample sample) => value = sample;

  void _handleError(Object error) => onError?.call(error);

  /// Reads the numeric field [key] of the latest sample, formatted with
  /// [decimals] decimals, or `-` if there is none.
  String number(String key, {int decimals = 2}) {
    Object? field = value?.values[key];
    return field is num ? field.toStringAsFixed(decimals) : "-";
  }

  /// Reads the field [key] of the latest sample as text, or `-`.
  String text(String key) => value?.values[key]?.toString() ?? "-";

  @override
  void dispose() {
    unawaited(detach());
    super.dispose();
  }
}

/// Holds the latest complete scan of a sensor that emits one sample per
/// scanned item (Wi-Fi, Bluetooth), recognised by a shared timestamp.
class LiveScan extends LiveSample {
  /// Creates an empty holder.
  LiveScan({super.onError});

  List<SensorSample> _items = <SensorSample>[];

  /// The samples of the latest scan.
  List<SensorSample> get items => List<SensorSample>.unmodifiable(_items);

  @override
  void handle(SensorSample sample) {
    if (sample.timestamp != value?.timestamp) {
      _items = <SensorSample>[];
    }
    _items.add(sample);
    super.handle(sample);
  }
}
