<p align="center">
  <img src="logo.svg" alt="urwalking sensors logo" width="160">
</p>

# urwalking_sensors

Cross-platform Flutter library for high-frequency multi-sensor recording and
streaming on Android and iOS.

## Packages

The library is split so an app only downloads the plugins for the sensors it
uses. Add `urwalking_sensors` plus the add-on packages you need.

| Package | Provides | Pulls in | Needs from the app |
| --- | --- | --- | --- |
| `urwalking_sensors` | `Sensor`, `Recorder`, `CsvSink`, `MemorySink`, interpolation | nothing (pure Dart) | – |
| `urwalking_sensors_motion` | accelerometer, gyroscope, magnetometer, barometer | `sensors_plus` | – |
| `urwalking_sensors_pedometer` | step count, pedestrian status | `pedometer` | Android: `ACTIVITY_RECOGNITION` permission; iOS: `NSMotionUsageDescription` |
| `urwalking_sensors_location` | GPS position | `geolocator` | location permission; iOS: `NSLocationWhenInUseUsageDescription` |
| `urwalking_sensors_compass` | heading | `flutter_compass` | – |
| `urwalking_sensors_wifi` | Wi-Fi scan (Android only) | `wifi_scan` | location permission, location service on |
| `urwalking_sensors_bluetooth` | Bluetooth LE scan | `flutter_blue_plus` | Android 12+: `BLUETOOTH_SCAN`; iOS: `NSBluetoothAlwaysUsageDescription` |

The library never asks for permissions itself: the app requests them (see
`example/lib/services/permission.dart`) before listening to a sensor. A
sensor without permission reports an error on its `samples` stream.

## Repository layout

| Path | What it is |
| --- | --- |
| `packages/` | The library packages above. Each exposes a single import, e.g. `package:urwalking_sensors_motion/urwalking_sensors_motion.dart`. |
| `example/` | The sensor host app, which demonstrates the library. `example/lib/sensors/ar_pose_sensor.dart` shows how to add a custom sensor. |
| `tools/receiver/` | Python PC receiver that collects and combines recordings |

The repo is a [pub workspace](https://dart.dev/tools/pub/workspaces): one
`flutter pub get` at the root resolves all packages and the example.

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
import "package:urwalking_sensors_motion/urwalking_sensors_motion.dart";

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

| Part | Status | Notes |
| --- | --- | --- |
| Motion, pedometer, GPS, compass, Wi-Fi, Bluetooth | ✅ in `packages/` | |
| ARCore pose | example app | custom sensor over the app's own platform channel |
| Camera capture | example app | native code in `example/android/.../MainActivity.kt`; needs to move into a plugin package |
| CSV output | ✅ `CsvSink` | same format as before, read by `tools/receiver` |
| Tar export over TCP / adb reverse | example app | `example/lib/services/sendDataToPi.dart`, to become a sink |
| Live timestamp stream | example app | `example/lib/services/streaming_service.dart`, to become a sink |

Known gaps:

- Timestamps are taken in Dart when a sample arrives, not by the sensor
  hardware, so they include platform channel latency (typically a few ms).
- Camera frames are timestamped natively with the wall clock, while sensors
  use `SensorClock`; both start from the same wall time but can drift apart if
  the system clock is adjusted during a recording.

## Development

```sh
flutter pub get                          # at the repo root, resolves everything
dart analyze packages example
(cd packages/urwalking_sensors && dart test)
(cd example && flutter test)
```

Run the demo app from `example/` with `flutter run`.

## Resources

- [Package by Layer vs Package by Feature](https://medium.com/sahibinden-technology/package-by-layer-vs-package-by-feature-7e89cde2ae3a) by M. Enes Oral on Medium
- [Guide to app architecture](https://docs.flutter.dev/app-architecture/guide) by Flutter
- [Testing Flutter Apps](https://docs.flutter.dev/testing/overview) by Flutter
- [Developing packages & plugins](https://docs.flutter.dev/packages-and-plugins/developing-packages) by Flutter
