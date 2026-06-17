import "dart:async";

import "package:flutter_compass/flutter_compass.dart";
import "package:geolocator/geolocator.dart";
import "package:pedometer/pedometer.dart";
import "package:sensors_plus/sensors_plus.dart";
import "package:urwalking_sensor_host/services/interpolation.dart";
import "package:urwalking_sensor_host/services/save_to_csv.dart";
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
  static const String _imageSensorName = "images";

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

  Future<void> finalizeRecording() async {
    if (_recordedSamples.isEmpty) return;

    const int targetHz = 20; // 50ms Raster

    //Group samples by sensor for easier interpolation
    Map<String, List<_SensorSample>> samplesBySensor = <String, List<_SensorSample>>{};
    for (_SensorSample sample in _recordedSamples) {
      samplesBySensor.putIfAbsent(sample.sensorName, () => <_SensorSample>[]).add(sample);
    }

    List<String> numericColumns = <String>[
      "acc_x", "acc_y", "acc_z",
      "com",
      "gps_accuracy", "gps_alt", "gps_heading", "gps_lat", "gps_lon", "gps_speed",
      "gyro_x", "gyro_y", "gyro_z",
      "mag_x", "mag_y", "mag_z",
      "bar"
    ];

    List<String> discreteColumns = <String>[
      "step_total", "step_session", "pedometer_status", "wifi_name_list", "wifi_sig_strength",
       "img_front","img_back" 
    ];


    List<String> csvHeader = <String>["timestamp", "delta_ms", ...numericColumns, ...discreteColumns];

    //nterpolation berechnen
    Map<String, List<DataPoint>> interpolatedSeries = <String, List<DataPoint>>{};

    void processSensorInterpolation(String sensorName, List<String> axes) {
      List<_SensorSample> samples = samplesBySensor[sensorName] ?? [];
      if (samples.length >= 3) {
        for (String axis in axes) {
          List<MeasuredPoint> measuredPoints = [
            for (var s in samples) MeasuredPoint(s.timestamp, double.parse(s.values[axis]!))
          ];
          interpolatedSeries[axis] = interpolate(measuredPoints, targetHz);
        }
      }
    }

    processSensorInterpolation(_accelerometerSensorName, ["acc_x", "acc_y", "acc_z"]);
    processSensorInterpolation(_compassSensorName, ["com"]);
    processSensorInterpolation(_gyroscopeSensorName, ["gyro_x", "gyro_y", "gyro_z"]);
    processSensorInterpolation(_magnetometerSensorName, ["mag_x", "mag_y", "mag_z"]);
    processSensorInterpolation(_barometerSensorName, ["bar"]);
    processSensorInterpolation(_locationSensorName, [
      "gps_accuracy", "gps_alt", "gps_heading", "gps_lat", "gps_lon", "gps_speed"
    ]);

    String referenceAxis = "acc_x";
    if (!interpolatedSeries.containsKey(referenceAxis) && interpolatedSeries.isNotEmpty) {
      referenceAxis = interpolatedSeries.keys.first;
    }

    List<DataPoint> timeline = interpolatedSeries[referenceAxis] ?? [];
    StringBuffer csvContent = StringBuffer();
    csvContent.writeln(csvHeader.join(","));

    String _formatTimestamp(DateTime timestamp) {
      DateTime localTime = timestamp.toLocal();
      String datePart =
          '${localTime.year.toString().padLeft(4, '0')}-'
          '${localTime.month.toString().padLeft(2, '0')}-'
          '${localTime.day.toString().padLeft(2, '0')}';
      String timePart =
          '${localTime.hour.toString().padLeft(2, '0')}:'
          '${localTime.minute.toString().padLeft(2, '0')}:'
          '${localTime.second.toString().padLeft(2, '0')}.'
          '${localTime.millisecond.toString().padLeft(3, '0')}';
      return "$datePart $timePart";
    }
    
    DateTime? lastTimestamp;
    // Hilfs-Strukturen für "Forward-Fill" (Letzten bekannten Wert halten, wenn die Interpolation endet)
    Map<String, String> lastValidNumericValues = {};
    List<_SensorSample> remainingImageSamples = List.from(samplesBySensor[_imageSensorName] ?? []);

    for (int i = 0; i < timeline.length; i++) {
      DateTime currentTimestamp = timeline[i].timestamp;
      
      String deltaStr = "";
      if (lastTimestamp != null) {
        deltaStr = currentTimestamp.difference(lastTimestamp).inMilliseconds.toString();
      }
      lastTimestamp = currentTimestamp;

      List<String> rowValues = <String>[
        _formatTimestamp(currentTimestamp),
        deltaStr
      ];

      // Numerische Werte aus der Interpolation, mit Forward-Fill, falls Interpolation endet
      for (String col in numericColumns) {
        if (interpolatedSeries.containsKey(col) && i < interpolatedSeries[col]!.length) {
          String val = interpolatedSeries[col]![i].value.toStringAsFixed(6);
          lastValidNumericValues[col] = val;
          rowValues.add(val);
        } else {
          if (col == "bar") {
            rowValues.add(barometerPressure > 0 ? barometerPressure.toStringAsFixed(6) : "");
          } else {
            rowValues.add(lastValidNumericValues[col] ?? "");
          }
        }
      }

      _SensorSample? matchedImageSample;
      for (var sample in remainingImageSamples) {
        if (sample.timestamp.difference(currentTimestamp).abs() < const Duration(milliseconds: 1500)) {
          matchedImageSample = sample;
          break;
        }
      }

      for (String col in discreteColumns) {
        if (col == "img_back") {
          rowValues.add(matchedImageSample != null ? (matchedImageSample.values["img_back"] ?? "") : "");
        } else if (col == "img_front") {
          rowValues.add(matchedImageSample != null ? (matchedImageSample.values["img_front"] ?? "") : "");
        } else if (col.startsWith("wifi")) {
          List<_SensorSample> wifiSamples = samplesBySensor[_wifiSensorName] ?? [];
          List<String> wifiNames = [];
          List<String> wifiSignals = [];
            
          for (var sample in wifiSamples) {
            if (sample.timestamp.difference(currentTimestamp).abs() < const Duration(seconds: 2)) {
              if (col == "wifi_name_list") wifiNames.add(sample.values["wifi_name_list"] ?? "");
              if (col == "wifi_sig_strength") wifiSignals.add(sample.values["wifi_sig_strength"] ?? "");
            }
          }
            
          String combinedWifi = col == "wifi_name_list" ? wifiNames.join(";") : wifiSignals.join(";");
          rowValues.add(combinedWifi.isNotEmpty ? '"$combinedWifi"' : "");
        } else {
            // Pedometer: Versuche aus den gemessenen Samples zu lesen, ansonsten direkter Fallback auf Live-Daten der Klasse!
            List<_SensorSample> pedoSteps = samplesBySensor[_pedometerSensorName] ?? [];
            List<_SensorSample> pedoStatus = samplesBySensor[_pedometerStatusSensorName] ?? [];
            
            String finalPedValue = "";
            if (col == "step_total") {
              for (var s in pedoSteps) { if (s.timestamp.isBefore(currentTimestamp)) finalPedValue = s.values["step_total"] ?? ""; }
              if (finalPedValue.isEmpty) finalPedValue = totalSteps.toString();
            } else if (col == "step_session") {
              for (var s in pedoSteps) { if (s.timestamp.isBefore(currentTimestamp)) finalPedValue = s.values["step_session"] ?? ""; }
              if (finalPedValue.isEmpty) finalPedValue = sessionSteps.toString();
            } else if (col == "pedometer_status") {
              for (var s in pedoStatus) { if (s.timestamp.isBefore(currentTimestamp)) finalPedValue = s.values["pedometer_status"] ?? ""; }
              if (finalPedValue.isEmpty) finalPedValue = pedometerStatus;
            }
            rowValues.add(finalPedValue);
          }
        }
      
      if (matchedImageSample != null) {remainingImageSamples.remove(matchedImageSample);}
      csvContent.writeln(rowValues.join(","));
    }

    await saveSingleCsvFile(fileName: "all_sensors_combined.csv", content: csvContent.toString());
    _recordedSamples.clear();
  }

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
  }
}
