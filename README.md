# urwalking_sensors

Cross-platform Flutter library for high-frequency multi-sensor recording and
streaming on Android and iOS.

## Repository layout

| Path | What it is |
| --- | --- |
| `lib/` | The library. `lib/urwalking_sensors.dart` is the only public import; everything else lives in `lib/src/`. |
| `lib/src/core/` | `Sensor`, `SensorSample`, `SampleSink`, `Recorder`, `SensorClock` |
| `lib/src/sensors/` | Built-in sensors |
| `lib/src/sinks/` | Built-in sinks (CSV, memory) |
| `lib/src/processing/` | Resampling / interpolation |
| `example/` | The sensor host app, which demonstrates the library |
| `tools/receiver/` | Python PC receiver that collects and combines recordings |
| `test/` | Library tests (`flutter test`) |

## Concepts

- **`Sensor`** produces a broadcast stream of `SensorSample`s. It is only
  active while something listens to it.
- **`SensorSample`** is the one data format for all sensors: a sensor id, a
  timestamp and a map of named values.
- **`SensorClock`** is the shared, monotonic time base. All built-in sensors
  use `SensorClock.shared`, so their samples can be aligned afterwards.
- **`SampleSink`** is where samples go: CSV files, memory, a network stream...
- **`Recorder`** connects a set of sensors to a set of sinks for one recording.

```dart
import "package:urwalking_sensors/urwalking_sensors.dart";

Recorder recorder = Recorder(
  sensors: <Sensor>[AccelerometerSensor(), GyroscopeSensor()],
  sinks: <SampleSink>[CsvSink(outputDirectory)],
);
await recorder.start();
// ...
await recorder.stop();
```

For a live display, listen to a sensor directly:

```dart
AccelerometerSensor().samples.listen((SensorSample sample) {
  print(sample.values["acc_x"]);
});
```

### Adding your own sensor

Extend `StreamSensor` and map your data source to `SensorSample`s. Take
timestamps from `clock` so the samples line up with the other sensors:

```dart
class MySensor extends StreamSensor {
  @override
  String get id => "my_sensor";

  @override
  Stream<SensorSample> openSource() => myDataStream.map(
    (MyEvent event) => SensorSample(
      sensorId: id,
      timestamp: clock.now(),
      values: <String, Object?>{"my_value": event.value},
    ),
  );
}
```

### Adding your own sink

Implement `SampleSink` (`open`, `add`, `close`). `add` is called for every
sample of every sensor, so keep it fast and buffer slow work.

## Migration status

The library is being extracted from the app in `example/`.

| Sensor | Library | Notes |
| --- | --- | --- |
| Accelerometer, gyroscope, magnetometer, barometer | ✅ | `sensors_plus` |
| Pedometer, GPS, compass, Wi-Fi scan, Bluetooth scan | ⏳ | still in `example/lib/services/sensors.dart` |
| Camera, ARCore pose | ⏳ | native code in `example/android/.../MainActivity.kt`; needs to move into a plugin (`android/`, `ios/`) |

| Sink | Library | Notes |
| --- | --- | --- |
| CSV files | ✅ | same format as before, read by `tools/receiver` |
| Tar export over TCP / adb reverse | ⏳ | `example/lib/services/sendDataToPi.dart` |
| Live timestamp stream | ⏳ | `example/lib/services/streaming_service.dart` |

## Development

```sh
flutter pub get
dart analyze
flutter test
```

Run the demo app from `example/` with `flutter run`.

## Resources

- [Package by Layer vs Package by Feature](https://medium.com/sahibinden-technology/package-by-layer-vs-package-by-feature-7e89cde2ae3a) by M. Enes Oral on Medium
- [Guide to app architecture](https://docs.flutter.dev/app-architecture/guide) by Flutter
- [Testing Flutter Apps](https://docs.flutter.dev/testing/overview) by Flutter
- [Developing packages & plugins](https://docs.flutter.dev/packages-and-plugins/developing-packages) by Flutter
