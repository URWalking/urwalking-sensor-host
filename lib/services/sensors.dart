import "dart:async";

import "package:pedometer/pedometer.dart";
import "package:sensors_plus/sensors_plus.dart";
import "package:urwalking_sensor_host/services/save_to_scv.dart";

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

  void startAccelerometer() {
    accelSub = accelerometerEventStream().listen((AccelerometerEvent event) {
      accelX = event.x;
      accelY = event.y;
      accelZ = event.z;
      if (shouldRecord?.call() ?? false) {
        unawaited(
          saveSensorSample(
            sensorName: "accelerometer",
            values: <String, String>{
              "x": accelX.toStringAsFixed(6),
              "y": accelY.toStringAsFixed(6),
              "z": accelZ.toStringAsFixed(6),
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
        unawaited(
          saveSensorSample(
            sensorName: "gyroscope",
            values: <String, String>{
              "x": gyroX.toStringAsFixed(6),
              "y": gyroY.toStringAsFixed(6),
              "z": gyroZ.toStringAsFixed(6),
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
          unawaited(
            saveSensorSample(
              sensorName: "pedometer",
              values: <String, String>{
                "event_type": "step_count",
                "total_steps": totalSteps.toString(),
                "session_steps": sessionSteps.toString(),
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
          unawaited(
            saveSensorSample(
              sensorName: "pedometer",
              values: <String, String>{
                "event_type": "status",
                "status": pedometerStatus,
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

  Future<void> dispose() async {
    await accelSub?.cancel();
    await gyroSub?.cancel();
    await stepSub?.cancel();
    await statusSub?.cancel();
  }
}
