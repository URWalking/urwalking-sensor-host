import "dart:async";

import "package:flutter_blue_plus/flutter_blue_plus.dart";
import "package:urwalking_sensors/urwalking_sensors.dart";

/// Nearby Bluetooth Low Energy devices.
///
/// Scans continuously and emits a snapshot every [snapshotInterval]: one
/// sample per device seen since the scan started, with its latest signal
/// strength. All samples of a snapshot share the same timestamp.
///
/// Fields:
/// - `bt_id`: the device id (MAC address on Android, a random UUID on iOS)
/// - `bt_name`: the advertised name, empty if none
/// - `bt_rssi`: signal strength in dBm
///
/// Requires the Bluetooth scan permission (Android 12+) or Bluetooth usage
/// (`NSBluetoothAlwaysUsageDescription`) on iOS, and Bluetooth turned on.
class BluetoothScanSensor extends StreamSensor {
  /// Creates a Bluetooth LE scan sensor.
  BluetoothScanSensor({
    super.clock,
    this.snapshotInterval = const Duration(seconds: 1),
  });

  /// How often a snapshot of the seen devices is emitted.
  final Duration snapshotInterval;

  @override
  String get id => "bluetooth";

  @override
  Future<bool> isAvailable() => FlutterBluePlus.isSupported;

  @override
  Stream<SensorSample> openSource() {
    List<ScanResult> latest = <ScanResult>[];
    StreamSubscription<List<ScanResult>>? results;
    Timer? timer;
    late StreamController<SensorSample> controller;

    void emitSnapshot() {
      DateTime timestamp = clock.now();
      for (ScanResult result in latest) {
        controller.add(_sample(result, timestamp));
      }
    }

    Future<void> start() async {
      results = FlutterBluePlus.onScanResults.listen(
        (List<ScanResult> update) => latest = update,
        onError: controller.addError,
      );
      try {
        // On iOS the adapter state is `unknown` until CoreBluetooth has
        // started up, and scanning before then fails with a
        // PlatformException, so wait for the first real state.
        BluetoothAdapterState state = await FlutterBluePlus.adapterState
            .firstWhere(
              (BluetoothAdapterState s) =>
                  s != BluetoothAdapterState.unknown &&
                  s != BluetoothAdapterState.turningOn,
            )
            .timeout(
              const Duration(seconds: 5),
              onTimeout: () => BluetoothAdapterState.unknown,
            );
        if (state != BluetoothAdapterState.on) {
          throw BluetoothScanException(
            "Cannot start Bluetooth scan: adapter is ${state.name}",
          );
        }
        await FlutterBluePlus.startScan(continuousUpdates: true);
      } on Exception catch (error, stackTrace) {
        controller.addError(error, stackTrace);
        return;
      }
      timer = Timer.periodic(snapshotInterval, (_) => emitSnapshot());
    }

    controller = StreamController<SensorSample>(
      onListen: () => unawaited(start()),
      onCancel: () async {
        timer?.cancel();
        await results?.cancel();
        if (FlutterBluePlus.isScanningNow) {
          await FlutterBluePlus.stopScan();
        }
        await controller.close();
      },
    );
    return controller.stream;
  }

  SensorSample _sample(ScanResult result, DateTime timestamp) {
    String name = result.device.platformName.isNotEmpty
        ? result.device.platformName
        : result.advertisementData.advName;
    return SensorSample(
      sensorId: id,
      timestamp: timestamp,
      values: <String, Object?>{
        "bt_id": result.device.remoteId.str,
        "bt_name": name,
        "bt_rssi": result.rssi,
      },
    );
  }
}

/// A Bluetooth scan could not be started, usually because Bluetooth is off
/// or the app is not allowed to use it.
class BluetoothScanException implements Exception {
  /// Creates an exception with a [message] for the user.
  const BluetoothScanException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => message;
}
