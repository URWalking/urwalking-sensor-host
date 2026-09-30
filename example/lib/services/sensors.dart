import "dart:async";
import "dart:io";

import "package:flutter/services.dart";
import "package:flutter_compass/flutter_compass.dart";
import "package:geolocator/geolocator.dart";
import "package:pedometer/pedometer.dart";
import "package:sensors_plus/sensors_plus.dart";
import "package:urwalking_sensor_host/services/bluetooth_service.dart";
import "package:urwalking_sensor_host/services/save_to_csv.dart";
import "package:urwalking_sensor_host/services/storage_utils.dart";
import "package:wifi_scan/wifi_scan.dart";

class _SensorSample {
  final DateTime timestamp;
  final String sensorName;
  final Map<String, String> values;

  _SensorSample({
    required this.timestamp,
    required this.sensorName,
    required this.values,
  });
}

class SensorService {
  // Accelerometer
  StreamSubscription<AccelerometerEvent>? accelSub;
  double accelX = 0, accelY = 0, accelZ = 0;

  // Gyroscope
  StreamSubscription<GyroscopeEvent>? gyroSub;
  double gyroX = 0, gyroY = 0, gyroZ = 0;

  // Magnetometer
  StreamSubscription<MagnetometerEvent>? magnetometerSub;
  double magnetometerX = 0, magnetometerY = 0, magnetometerZ = 0;

  // Barometer
  StreamSubscription<BarometerEvent>? barometerSub;
  double barometerPressure = 0;

  // Pedometer
  StreamSubscription<StepCount>? stepSub;
  StreamSubscription<PedestrianStatus>? statusSub;
  int totalSteps = 0;
  int sessionSteps = 0;
  int? sessionBaseline;
  String pedometerStatus = "unknown";

  // Location (GPS)
  StreamSubscription<Position>? locationSub;
  StreamSubscription<ServiceStatus>? locationServiceStatusSub;
  double? locationLatitude;
  double? locationLongitude;
  double? locationAltitude;
  double? locationAccuracy;
  double? locationSpeed;
  double? locationHeading;
  bool locationServiceEnabled = false;
  String locationStatus = "unknown";

  // Compass
  StreamSubscription<CompassEvent>? compassSub;
  double? compassHeading;

  // WiFi
  late Timer? _wifiScanTimer;
  List<WiFiAccessPoint> wifiAccessPoints = <WiFiAccessPoint>[];

  // Bluetooth
  final BluetoothService _bluetoothService = BluetoothService();
  List<BtDevice> bluetoothDevices = <BtDevice>[];

  // Callbacks for updates
  Function(double, double, double)? onAccelerometerUpdate;
  Function(double, double, double)? onGyroscopeUpdate;
  Function(double, double, double)? onMagnetometerUpdate;
  Function(double)? onBarometerUpdate;
  Function(int, int)? onPedometerUpdate;
  Function(String)? onStatusUpdate;
  Function(double, double, double?, double?, double?, double?)? onLocationUpdate;
  Function(bool)? onLocationServiceStatusUpdate;
  Function(String)? onError;
  Function()? shouldRecord;
  Function(double?)? onCompassUpdate;
  Function(List<WiFiAccessPoint>)? onWifiScanUpdate;
  Function(List<BtDevice>)? onBluetoothScanUpdate;

  // Recording state
  final List<_SensorSample> _recordedSamples = <_SensorSample>[];

  static const String _accelerometerSensorName = "accelerometer";
  static const String _gyroscopeSensorName = "gyroscope";
  static const String _magnetometerSensorName = "magnetometer";
  static const String _barometerSensorName = "barometer";
  static const String _pedometerSensorName = "pedometer_steps";
  static const String _pedometerStatusSensorName = "pedometer_status";
  static const String _locationSensorName = "location";
  static const String _compassSensorName = "compass";
  static const String _wifiSensorName = "wifi";
  static const String _bluetoothSensorName = "bluetooth";
  static const String _imageSensorName = "images";
  static const String _arposeSensorName = "arpose";

  static const EventChannel _arPoseChannel =
      EventChannel("com.example.urwalking_sensor_host/arpose");
  static const MethodChannel _arMethodChannel =
      MethodChannel("com.example.urwalking_sensor_host/camera");

  StreamSubscription<dynamic>? _arPoseSub;

  double arTx = 0;
  double arTy = 0;
  double arTz = 0;
  String arTrackingState = "STOPPED";
  Function(double, double, double, String)? onArPoseUpdate;

  // Sensor start/stop methods

  void startAccelerometer() {
    accelSub = accelerometerEventStream().listen((AccelerometerEvent event) {
      accelX = event.x;
      accelY = event.y;
      accelZ = event.z;
      if (shouldRecord?.call() ?? false) {
        _recordedSamples.add(
          _SensorSample(
            timestamp: DateTime.now(),
            sensorName: _accelerometerSensorName,
            values: <String, String>{
              "acc_x": accelX.toStringAsFixed(6),
              "acc_y": accelY.toStringAsFixed(6),
              "acc_z": accelZ.toStringAsFixed(6),
            },
          ),
        );
      }
      onAccelerometerUpdate?.call(accelX, accelY, accelZ);
    });
  }

  void startGyroscope() {
    gyroSub = gyroscopeEventStream().listen((GyroscopeEvent event) {
      gyroX = event.x;
      gyroY = event.y;
      gyroZ = event.z;
      if (shouldRecord?.call() ?? false) {
        _recordedSamples.add(
          _SensorSample(
            timestamp: DateTime.now(),
            sensorName: _gyroscopeSensorName,
            values: <String, String>{
              "gyro_x": gyroX.toStringAsFixed(6),
              "gyro_y": gyroY.toStringAsFixed(6),
              "gyro_z": gyroZ.toStringAsFixed(6),
            },
          ),
        );
      }
      onGyroscopeUpdate?.call(gyroX, gyroY, gyroZ);
    });
  }

  void startMagnetometer() {
    magnetometerSub = magnetometerEventStream().listen((
      MagnetometerEvent event,
    ) {
      magnetometerX = event.x;
      magnetometerY = event.y;
      magnetometerZ = event.z;
      if (shouldRecord?.call() ?? false) {
        _recordedSamples.add(
          _SensorSample(
            timestamp: DateTime.now(),
            sensorName: _magnetometerSensorName,
            values: <String, String>{
              "mag_x": magnetometerX.toStringAsFixed(6),
              "mag_y": magnetometerY.toStringAsFixed(6),
              "mag_z": magnetometerZ.toStringAsFixed(6),
            },
          ),
        );
      }
      onMagnetometerUpdate?.call(magnetometerX, magnetometerY, magnetometerZ);
    });
  }

  void startBarometer() {
    barometerSub = barometerEventStream().listen((BarometerEvent event) {
      barometerPressure = event.pressure;
      if (shouldRecord?.call() ?? false) {
        _recordedSamples.add(
          _SensorSample(
            timestamp: DateTime.now(),
            sensorName: _barometerSensorName,
            values: <String, String>{
              "bar": barometerPressure.toStringAsFixed(6),
            },
          ),
        );
      }
      onBarometerUpdate?.call(barometerPressure);
    });
  }

  void startPedometer() {
    stepSub = Pedometer.stepCountStream.listen(
      (StepCount event) {
        totalSteps = event.steps;
        sessionBaseline ??= event.steps;
        int delta = totalSteps - sessionBaseline!;
        sessionSteps = delta < 0 ? 0 : delta;
        if (shouldRecord?.call() ?? false) {
          _recordedSamples.add(
            _SensorSample(
              timestamp: DateTime.now(),
              sensorName: _pedometerSensorName,
              values: <String, String>{
                "step_total": totalSteps.toString(),
                "step_session": sessionSteps.toString(),
              },
            ),
          );
        }
        onPedometerUpdate?.call(totalSteps, sessionSteps);
      },
      onError: (error) {
        onError?.call(error.toString());
      },
    );

    statusSub = Pedometer.pedestrianStatusStream.listen(
      (PedestrianStatus event) {
        pedometerStatus = event.status;
        if (shouldRecord?.call() ?? false) {
          _recordedSamples.add(
            _SensorSample(
              timestamp: DateTime.now(),
              sensorName: _pedometerStatusSensorName,
              values: <String, String>{"pedometer_status": pedometerStatus},
            ),
          );
        }
        onStatusUpdate?.call(pedometerStatus);
      },
      onError: (error) {
        onError?.call(error.toString());
      },
    );
  }

  void startCompass() {
    compassSub = FlutterCompass.events?.listen((CompassEvent event) {
      compassHeading = event.heading != null ? event.heading! % 360 : null;
      if (shouldRecord?.call() ?? false) {
        _recordedSamples.add(
          _SensorSample(
            timestamp: DateTime.now(),
            sensorName: _compassSensorName,
            values: <String, String>{
              "com": compassHeading!.toStringAsFixed(6),
            },
          ),
        );
      }
      onCompassUpdate?.call(compassHeading);
    });
  }


  // WiFi
  Future<void> startWifi() async {
    await _runWifiScan(); // immediate first scan
    _wifiScanTimer = Timer.periodic(
      const Duration(seconds: 30),
      // We need a 30s timer because Android requires at least 30s between scans,
      //it does not give any new results if we scan more frequently, just wastes battery.
      (_) => _runWifiScan(),
    );
  }

  Future<void> _runWifiScan() async {
    final CanStartScan canScan = await WiFiScan.instance.canStartScan();
    if (canScan != CanStartScan.yes) {
      onError?.call("Cannot start WiFi scan: $canScan");
      return;
    }

    await WiFiScan.instance.startScan();

    final CanGetScannedResults canGet = await WiFiScan.instance
        .canGetScannedResults();
    if (canGet != CanGetScannedResults.yes) {
      onError?.call("Cannot get WiFi scan results: $canGet");
      return;
    }

    wifiAccessPoints = await WiFiScan.instance.getScannedResults();
    onWifiScanUpdate?.call(wifiAccessPoints);

    if (shouldRecord?.call() ?? false) {
      for (final WiFiAccessPoint ap in wifiAccessPoints) {
        _recordedSamples.add(
          _SensorSample(
            timestamp: DateTime.now(),
            sensorName: _wifiSensorName,
            values: <String, String>{
              "wifi_name_list": ap.ssid.isNotEmpty ? ap.ssid : "<hidden>",
              "wifi_sig_strength": ap.level.toString(),
            },
          ),
        );
      }
    }
  }

  // Bluetooth

  Future<void> startBluetooth() async {
    _bluetoothService.onSnapshot = (List<BtDevice> devices) {
      bluetoothDevices = devices;
      onBluetoothScanUpdate?.call(devices);
      if (shouldRecord?.call() ?? false) {
        for (final BtDevice device in devices) {
          _recordedSamples.add(
            _SensorSample(
              timestamp: DateTime.now(),
              sensorName: _bluetoothSensorName,
              values: <String, String>{
                "bt_id": device.id,
                "bt_name": device.name,
                "bt_rssi": device.rssi.toString(),
              },
            ),
          );
        }
      }
    };
    try {
      await _bluetoothService.startScan();
    } catch (_) {}
  }

  Future<void> stopBluetooth() async {
    try {
      await _bluetoothService.stopScan();
    } catch (_) {}
    bluetoothDevices = [];
  }

  // Location (GPS)

  /// Starts listening to the GPS position stream.
  /// Call only after location permission has been granted.
  void startLocation() {
    // Monitor service on/off so the UI can react.
    locationServiceStatusSub = GeolocatorPlatform.instance
        .getServiceStatusStream()
        .handleError((error) async {
          await locationServiceStatusSub?.cancel();
          locationServiceStatusSub = null;
          onError?.call("Location service stream error: $error");
        })
        .listen((ServiceStatus status) async {
          locationServiceEnabled = status == ServiceStatus.enabled;
          onLocationServiceStatusUpdate?.call(locationServiceEnabled);

          if (!locationServiceEnabled && locationSub != null) {
            await locationSub?.cancel();
            locationSub = null;
            locationStatus = "service disabled";
          } else if (locationServiceEnabled && locationSub == null) {
            _startPositionStream();
          }
        });

    _startPositionStream();
  }

  void _startPositionStream() {
    const LocationSettings settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0, // receive every update
    );

    locationSub = GeolocatorPlatform.instance
        .getPositionStream(locationSettings: settings)
        .handleError((error) async {
          await locationSub?.cancel();
          locationSub = null;
          locationStatus = "error";
          onError?.call("Location stream error: $error");
        })
        .listen((Position position) {
          locationLatitude = position.latitude;
          locationLongitude = position.longitude;
          locationAltitude = position.altitude;
          locationAccuracy = position.accuracy;
          locationSpeed = position.speed;
          locationHeading = position.heading;
          locationStatus = "active";

          if (shouldRecord?.call() ?? false) {
            _recordedSamples.add(
              _SensorSample(
                timestamp: position.timestamp,
                sensorName: _locationSensorName,
                values: <String, String>{
                  "gps_lat": position.latitude.toStringAsFixed(8),
                  "gps_lon": position.longitude.toStringAsFixed(8),
                  "gps_alt": position.altitude.toStringAsFixed(3),
                  "gps_accuracy": position.accuracy.toStringAsFixed(3),
                  "gps_speed": position.speed.toStringAsFixed(3),
                  "gps_heading": position.heading.toStringAsFixed(3),
                },
              ),
            );
          }

          onLocationUpdate?.call(
            position.latitude,
            position.longitude,
            position.altitude,
            position.accuracy,
            position.speed,
            position.heading,
          );
        });
  }

  //Camera
  void recordImageBack(String filename) {
    if (shouldRecord?.call() ?? false) {
      _recordedSamples.add(_SensorSample(
        timestamp: DateTime.now(),
        sensorName: _imageSensorName,
        values: {"img_back": filename, "img_front": ""},
      ));
    }
  }

  void recordImageFront(String filename) {
    if (shouldRecord?.call() ?? false) {
      _recordedSamples.add(_SensorSample(
        timestamp: DateTime.now(),
        sensorName: _imageSensorName,
        values: {"img_back": "", "img_front": filename},
      ));
    }
  }

  /// Starts ARCore pose tracking and returns the id of the camera ARCore
  /// ends up sharing with the native capture pipeline (via SharedCamera), or
  /// null if ARCore isn't supported on this device.
  Future<String?> startArPose() async {
    try {
      String? cameraId = await _arMethodChannel.invokeMethod<String>(
        "startArPose",
      );
      _arPoseSub = _arPoseChannel.receiveBroadcastStream().listen(
        (dynamic data) {
          Map<String, dynamic> pose =
              Map<String, dynamic>.from(data as Map);
          arTx = (pose["tx"] as num).toDouble();
          arTy = (pose["ty"] as num).toDouble();
          arTz = (pose["tz"] as num).toDouble();
          arTrackingState = pose["tracking"] as String;
          if (shouldRecord?.call() ?? false) {
            _recordedSamples.add(_SensorSample(
              timestamp: DateTime.now(),
              sensorName: _arposeSensorName,
              values: <String, String>{
                "ar_tx": arTx.toStringAsFixed(6),
                "ar_ty": arTy.toStringAsFixed(6),
                "ar_tz": arTz.toStringAsFixed(6),
                "ar_qx": (pose["qx"] as num).toStringAsFixed(6),
                "ar_qy": (pose["qy"] as num).toStringAsFixed(6),
                "ar_qz": (pose["qz"] as num).toStringAsFixed(6),
                "ar_qw": (pose["qw"] as num).toStringAsFixed(6),
                "ar_tracking": arTrackingState,
              },
            ));
          }
          onArPoseUpdate?.call(arTx, arTy, arTz, arTrackingState);
        },
        onError: (dynamic _) {},
      );
      return cameraId;
    } on PlatformException catch (_) {
      // ARCore not supported, skip silently
      return null;
    }
  }

  Future<void> stopArPose() async {
    await _arPoseSub?.cancel();
    _arPoseSub = null;
    try {
      await _arMethodChannel.invokeMethod<void>("stopArPose");
    } on PlatformException catch (_) {}
    arTrackingState = "STOPPED";
  }

  void addImageRecord(String filename, DateTime timestamp) {
    _recordedSamples.add(_SensorSample(
      timestamp: timestamp,
      sensorName: _imageSensorName,
      values: {"img_back": "", "img_front": filename},
    ));
  }

  Future<void> stopLocation() async {
    await locationSub?.cancel();
    locationSub = null;
    await locationServiceStatusSub?.cancel();
    locationServiceStatusSub = null;
    locationStatus = "stopped";
  }

  // Session helpers

  void resetSessionSteps() {
    sessionBaseline = totalSteps;
    sessionSteps = 0;
  }

  // Recording / CSV

  /// Clears any previously recorded CSV files from the logs directory
  Future<void> clearPreviousCsvFiles() async {
    try {
      Directory logsDir = await getLogsDirectory();
      if (!await logsDir.exists()) return;
      await for (FileSystemEntity entity in logsDir.list()) {
        if (entity is File && entity.path.endsWith("_raw.csv")) {
          await entity.delete();
        }
      }
    } catch (e) {
      print("[CSV] Failed to clear previous CSV files: $e");
    }
  }

  Future<void> finalizeRecording() async {
    if (_recordedSamples.isEmpty) return;

    Map<String, List<_SensorSample>> samplesBySensor = <String, List<_SensorSample>>{};
    for (_SensorSample sample in _recordedSamples) {
      samplesBySensor
          .putIfAbsent(sample.sensorName, () => <_SensorSample>[])
          .add(sample);
    }

    for (String sensorName in samplesBySensor.keys) {
      List<_SensorSample> samples = samplesBySensor[sensorName]!;
      if (samples.isEmpty) continue;

      List<String> columns = samples.first.values.keys.toList();
      StringBuffer csv = StringBuffer();
      csv.writeln(["phone_ts_ms", ...columns].join(","));

      for (_SensorSample sample in samples) {
        List<String> row = <String>[
          sample.timestamp.millisecondsSinceEpoch.toString(),
          ...columns.map((String col) => _escapeRaw(sample.values[col] ?? "")),
        ];
        csv.writeln(row.join(","));
      }

      await saveSingleCsvFile(
        fileName: "${sensorName}_raw.csv",
        content: csv.toString(),
      );
    }

    _recordedSamples.clear();
  }

  String _escapeRaw(String v) =>
      (v.contains(",") || v.contains('"') || v.contains("\n"))
          ? '"${v.replaceAll('"', '""')}"'
          : v;

  Future<void> dispose() async {
    await accelSub?.cancel();
    await gyroSub?.cancel();
    await magnetometerSub?.cancel();
    await barometerSub?.cancel();
    await stepSub?.cancel();
    await statusSub?.cancel();
    await locationSub?.cancel();
    await locationServiceStatusSub?.cancel();
    await compassSub?.cancel();
    _wifiScanTimer?.cancel();
    await stopBluetooth();
    await stopArPose();
  }
}
