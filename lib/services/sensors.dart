import "dart:async";

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

  // Pedometer
  StreamSubscription<StepCount>? stepSub;
  StreamSubscription<PedestrianStatus>? statusSub;
  int totalSteps = 0;
  int sessionSteps = 0;
  int? sessionBaseline;
  String pedometerStatus = "unknown";

  // Callbacks for updates
  Function(double, double, double)? onAccelerometerUpdate;
  Function(double, double, double)? onGyroscopeUpdate;
  Function(int, int)? onPedometerUpdate;
  Function(String)? onStatusUpdate;
  Function(String)? onError;
  Function()? shouldRecord;

  // Recording state
  final List<_SensorSample> _recordedSamples = <_SensorSample>[];

  static const String _accelerometerSensorName = "accelerometer";
  static const String _gyroscopeSensorName = "gyroscope";
  static const String _pedometerSensorName = "pedometer_steps";
  static const String _pedometerStatusSensorName = "pedometer_status";

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

  void startPedometer() {
    stepSub = Pedometer.stepCountStream.listen(
      (StepCount event) {
        totalSteps = event.steps;
        sessionBaseline ??= event.steps;
        sessionSteps = totalSteps - sessionBaseline!;
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
              values: <String, String>{
                "pedometer_status": pedometerStatus,
              },
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

  void resetSessionSteps() {
    sessionBaseline = totalSteps;
  }

  Future<void> finalizeRecording() async {
    // Group samples by sensor
    Map<String, List<_SensorSample>> samplesBySensor =
        <String, List<_SensorSample>>{};
    for (_SensorSample sample in _recordedSamples) {
      samplesBySensor
          .putIfAbsent(sample.sensorName, () => <_SensorSample>[])
          .add(sample);
    }

    // First pass: Save raw data to raw files
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
          isInterpolated: false,
          fileType: "raw",
        );
      }
    }

    // Second pass: Save interpolated data to interpolated files
    for (MapEntry<String, List<_SensorSample>> entry
        in samplesBySensor.entries) {
      String sensorName = entry.key;
      List<_SensorSample> samples = entry.value;

      if (samples.isEmpty) {
        continue;
      }

      if (sensorName == _accelerometerSensorName ||
          sensorName == _gyroscopeSensorName) {
        // Interpolate continuous sensor data
        await _interpolateAndSaveContinuousSensor(sensorName, samples);
      }
    }

    // Clear recorded samples after saving
    _recordedSamples.clear();
  }

  Future<void> _interpolateAndSaveContinuousSensor(
    String sensorName,
    List<_SensorSample> samples,
  ) async {
    const int targetSamplesPerSecond = 20;

    // Extract axes from samples (for accel/gyro this is acc_x, acc_y, acc_z or gyro_x, gyro_y, gyro_z).
    List<String> axes = samples.first.values.keys.toList();

    // Need enough source samples to run cubic interpolation.
    if (samples.length < 3) {
      for (_SensorSample sample in samples) {
        await saveSensorSample(
          sensorName: sensorName,
          values: sample.values,
          timestamp: sample.timestamp,
          isInterpolated: false,
          fileType: "interpolated",
        );
      }
      return;
    }

    Map<String, List<DataPoint>> axisSeries = <String, List<DataPoint>>{};
    for (String axis in axes) {
      List<MeasuredPoint> measuredPoints = <MeasuredPoint>[
        for (_SensorSample sample in samples)
          MeasuredPoint(sample.timestamp, double.parse(sample.values[axis]!)),
      ];

      axisSeries[axis] = interpolate(measuredPoints, targetSamplesPerSecond);
    }

    // All axes use the same timestamp grid; use first axis as canonical timeline.
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
        fileType: "interpolated",
      );
    }
  }

  Future<void> dispose() async {
    await accelSub?.cancel();
    await gyroSub?.cancel();
    await stepSub?.cancel();
    await statusSub?.cancel();
  }

}
