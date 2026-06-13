import "dart:async";

import "package:flutter_compass/flutter_compass.dart";
import "package:geolocator/geolocator.dart";
import "package:pedometer/pedometer.dart";
import "package:sensors_plus/sensors_plus.dart";
import "package:urwalking_sensor_host/services/interpolation.dart";
import "package:urwalking_sensor_host/services/save_to_csv.dart";

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

  // Callbacks for updates
  Function(double, double, double)? onAccelerometerUpdate;
  Function(double, double, double)? onGyroscopeUpdate;
  Function(double, double, double)? onMagnetometerUpdate;
  Function(double)? onBarometerUpdate;
  Function(int, int)? onPedometerUpdate;
  Function(String)? onStatusUpdate;
  Function(double, double, double?, double?, double?, double?)?
  onLocationUpdate;
  Function(bool)? onLocationServiceStatusUpdate;
  Function(String)? onError;
  Function()? shouldRecord;
  Function(double?)? onCompassUpdate;

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

  // ─── Existing sensors ────────────────────────────────────────────────────────

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

  // Compass
  void startCompass() {
    compassSub = FlutterCompass.events?.listen((CompassEvent event) {
      compassHeading = event.heading != null ? event.heading! % 360 : null;
      if (shouldRecord?.call() ?? false) {
        _recordedSamples.add(
          _SensorSample(
            timestamp: DateTime.now(),
            sensorName: _compassSensorName,
            values: <String, String>{
              "heading": compassHeading!.toStringAsFixed(6),
            },
          ),
        );
      }
      onCompassUpdate?.call(compassHeading);
    });
  }

  // ─── Location (GPS) ──────────────────────────────────────────────────────────

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
                  "lat": position.latitude.toStringAsFixed(8),
                  "lon": position.longitude.toStringAsFixed(8),
                  "alt": position.altitude.toStringAsFixed(3),
                  "accuracy": position.accuracy.toStringAsFixed(3),
                  "speed": position.speed.toStringAsFixed(3),
                  "heading": position.heading.toStringAsFixed(3),
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

  Future<void> stopLocation() async {
    await locationSub?.cancel();
    locationSub = null;
    await locationServiceStatusSub?.cancel();
    locationServiceStatusSub = null;
    locationStatus = "stopped";
  }

  // ─── Session helpers ─────────────────────────────────────────────────────────

  void resetSessionSteps() {
    sessionBaseline = totalSteps;
    sessionSteps = 0;
  }

  // ─── Recording / CSV ─────────────────────────────────────────────────────────

  Future<void> finalizeRecording() async {
    // Group samples by sensor
    Map<String, List<_SensorSample>> samplesBySensor =
        <String, List<_SensorSample>>{};
    for (_SensorSample sample in _recordedSamples) {
      samplesBySensor
          .putIfAbsent(sample.sensorName, () => <_SensorSample>[])
          .add(sample);
    }

    // First pass: raw files for every sensor
    for (MapEntry<String, List<_SensorSample>> entry
        in samplesBySensor.entries) {
      String sensorName = entry.key;
      List<_SensorSample> samples = entry.value;
      if (samples.isEmpty) {
        continue;
      }

      for (_SensorSample sample in samples) {
        await saveSensorSample(
          sensorName: sensorName,
          values: sample.values,
          timestamp: sample.timestamp,
          fileType: "raw",
        );
      }
    }

    // Second pass: interpolated files for continuous numeric sensors
    const Set<String> interpolatableSensors = <String>{
      _accelerometerSensorName,
      _gyroscopeSensorName,
      _magnetometerSensorName,
      _barometerSensorName,
      _locationSensorName,
      _compassSensorName,
    };

    for (MapEntry<String, List<_SensorSample>> entry
        in samplesBySensor.entries) {
      String sensorName = entry.key;
      List<_SensorSample> samples = entry.value;
      if (samples.isEmpty) {
        continue;
      }

      if (interpolatableSensors.contains(sensorName)) {
        await _interpolateAndSaveContinuousSensor(sensorName, samples);
      }
    }

    _recordedSamples.clear();
  }

  Future<void> _interpolateAndSaveContinuousSensor(
    String sensorName,
    List<_SensorSample> samples,
  ) async {
    const int targetSamplesPerSecond = 20;

    List<String> axes = samples.first.values.keys.toList();

    // Location is low-frequency GPS — interpolate at 1 Hz instead of 20 Hz
    // to avoid fabricating positions between fixes.
    int targetHz = sensorName == _locationSensorName
        ? 1
        : targetSamplesPerSecond;

    if (samples.length < 3) {
      for (_SensorSample sample in samples) {
        await saveSensorSample(
          sensorName: sensorName,
          values: sample.values,
          timestamp: sample.timestamp,
        );
      }
      return;
    }

    Map<String, List<DataPoint>> axisSeries = <String, List<DataPoint>>{};
    for (String axis in axes) {
      // heading / bearing needs circular interpolation — for simplicity we
      // keep it as a raw numeric axis; consumers should wrap at 360° themselves.
      List<MeasuredPoint> measuredPoints = <MeasuredPoint>[
        for (_SensorSample sample in samples)
          MeasuredPoint(sample.timestamp, double.parse(sample.values[axis]!)),
      ];
      axisSeries[axis] = interpolate(measuredPoints, targetHz);
    }

    String referenceAxis = axes.first;
    List<DataPoint> timeline = axisSeries[referenceAxis]!;

    for (int i = 0; i < timeline.length; i++) {
      DateTime timestamp = timeline[i].timestamp;
      Map<String, String> rowValues = <String, String>{};
      bool isInterpolatedRow = false;

      for (String axis in axes) {
        DataPoint point = axisSeries[axis]![i];
        rowValues[axis] = point.value.toStringAsFixed(6);
        if (point is InterpolatedPoint) {
          isInterpolatedRow = true;
        }
      }

      await saveSensorSample(
        sensorName: sensorName,
        values: rowValues,
        timestamp: timestamp,
        isInterpolated: isInterpolatedRow,
      );
    }
  }

  // ─── Dispose ─────────────────────────────────────────────────────────────────

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
  }
}
