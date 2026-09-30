import "dart:async";

import "package:flutter_blue_plus/flutter_blue_plus.dart";

class BtDevice {
  final String id;
  final String name;
  final int rssi;
  const BtDevice({required this.id, required this.name, required this.rssi});
}

class BluetoothService {
  StreamSubscription<List<ScanResult>>? _scanSub;
  List<BtDevice> _latestDevices = [];
  Timer? _snapshotTimer;

  Function(List<BtDevice>)? onSnapshot;

  Future<void> startScan() async {
    await FlutterBluePlus.startScan(continuousUpdates: true);

    _scanSub = FlutterBluePlus.onScanResults.listen((List<ScanResult> results) {
      _latestDevices = results.map((ScanResult r) {
        String name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : r.advertisementData.advName;
        return BtDevice(id: r.device.remoteId.str, name: name, rssi: r.rssi);
      }).toList();
    });

    _snapshotTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      onSnapshot?.call(List<BtDevice>.unmodifiable(_latestDevices));
    });
  }

  Future<void> stopScan() async {
    _snapshotTimer?.cancel();
    _snapshotTimer = null;
    await _scanSub?.cancel();
    _scanSub = null;
    await FlutterBluePlus.stopScan();
    _latestDevices = [];
  }
}
