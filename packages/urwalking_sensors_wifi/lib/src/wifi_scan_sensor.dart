import "dart:async";

import "package:urwalking_sensors/urwalking_sensors.dart";
import "package:wifi_scan/wifi_scan.dart";

/// Nearby Wi-Fi access points, from periodic scans. **Android only**: iOS
/// does not let apps scan for Wi-Fi networks.
///
/// Each scan emits one sample per access point, all with the same timestamp.
///
/// Fields:
/// - `wifi_name_list`: the network name (SSID), `<hidden>` if not broadcast
/// - `wifi_bssid`: the access point's MAC address, unique per access point
/// - `wifi_sig_strength`: signal strength in dBm
///
/// Requires location permission, and the location service must be on.
class WifiScanSensor extends StreamSensor {
  /// Creates a Wi-Fi scan sensor that scans every [scanInterval].
  ///
  /// Android throttles apps to 4 scans per 2 minutes, so intervals below
  /// 30 seconds mostly repeat the previous results.
  WifiScanSensor({
    super.clock,
    this.scanInterval = const Duration(seconds: 30),
  });

  /// How often a scan is started.
  final Duration scanInterval;

  @override
  String get id => "wifi";

  @override
  Future<bool> isAvailable() async =>
      await WiFiScan.instance.canStartScan(askPermissions: false) !=
      CanStartScan.notSupported;

  @override
  Stream<SensorSample> openSource() {
    Timer? timer;
    late StreamController<SensorSample> controller;

    Future<void> scan() async {
      try {
        (await _scan()).forEach(controller.add);
      } on Exception catch (error, stackTrace) {
        controller.addError(error, stackTrace);
      }
    }

    controller = StreamController<SensorSample>(
      onListen: () {
        unawaited(scan());
        timer = Timer.periodic(scanInterval, (_) => unawaited(scan()));
      },
      onCancel: () async {
        timer?.cancel();
        await controller.close();
      },
    );
    return controller.stream;
  }

  Future<List<SensorSample>> _scan() async {
    WiFiScan wifi = WiFiScan.instance;
    CanStartScan canStart = await wifi.canStartScan(askPermissions: false);
    if (canStart != CanStartScan.yes) {
      throw WifiScanException("Cannot start Wi-Fi scan: ${canStart.name}");
    }
    await wifi.startScan();
    CanGetScannedResults canGet = await wifi.canGetScannedResults(
      askPermissions: false,
    );
    if (canGet != CanGetScannedResults.yes) {
      throw WifiScanException("Cannot get Wi-Fi scan results: ${canGet.name}");
    }
    List<WiFiAccessPoint> accessPoints = await wifi.getScannedResults();
    DateTime timestamp = clock.now();
    return <SensorSample>[
      for (WiFiAccessPoint accessPoint in accessPoints)
        SensorSample(
          sensorId: id,
          timestamp: timestamp,
          values: <String, Object?>{
            "wifi_name_list": accessPoint.ssid.isEmpty
                ? "<hidden>"
                : accessPoint.ssid,
            "wifi_bssid": accessPoint.bssid,
            "wifi_sig_strength": accessPoint.level,
          },
        ),
    ];
  }
}

/// A Wi-Fi scan could not be started or its results could not be read,
/// usually because of missing permissions or a disabled location service.
class WifiScanException implements Exception {
  /// Creates an exception with a [message] for the user.
  const WifiScanException(this.message);

  /// What went wrong.
  final String message;

  @override
  String toString() => message;
}
