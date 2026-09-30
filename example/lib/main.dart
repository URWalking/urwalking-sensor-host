import "dart:async";
import "dart:io";

import "package:flutter/material.dart";
import "package:permission_handler/permission_handler.dart";
import "package:urwalking_sensor_host/sensors/ar_pose_sensor.dart";
import "package:urwalking_sensor_host/services/camera_service.dart";
import "package:urwalking_sensor_host/services/image_log.dart";
import "package:urwalking_sensor_host/services/permission.dart";
import "package:urwalking_sensor_host/services/storage_utils.dart";
import "package:urwalking_sensor_host/widgets/error_list.dart";
import "package:urwalking_sensor_host/widgets/live_sample.dart";
import "package:urwalking_sensor_host/widgets/permission_buttons.dart";
import "package:urwalking_sensor_host/widgets/recording_controls.dart";
import "package:urwalking_sensor_host/widgets/sensor_card.dart";
import "package:urwalking_sensors/urwalking_sensors.dart";
import "package:urwalking_sensors_bluetooth/urwalking_sensors_bluetooth.dart";
import "package:urwalking_sensors_compass/urwalking_sensors_compass.dart";
import "package:urwalking_sensors_location/urwalking_sensors_location.dart";
import "package:urwalking_sensors_motion/urwalking_sensors_motion.dart";
import "package:urwalking_sensors_network/urwalking_sensors_network.dart";
import "package:urwalking_sensors_pedometer/urwalking_sensors_pedometer.dart";
import "package:urwalking_sensors_wifi/urwalking_sensors_wifi.dart";

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: "Sensor Host",
    theme: ThemeData(useMaterial3: true),
    home: const SensorDashboard(),
  );
}

class SensorDashboard extends StatefulWidget {
  const SensorDashboard({super.key});

  @override
  State<SensorDashboard> createState() => _SensorDashboardState();
}

class _SensorDashboardState extends State<SensorDashboard> {
  late PermissionService _permissionService;
  late CameraService _cameraService;

  // Sensors
  final AccelerometerSensor _accelerometer = AccelerometerSensor();
  final GyroscopeSensor _gyroscope = GyroscopeSensor();
  final MagnetometerSensor _magnetometer = MagnetometerSensor();
  final BarometerSensor _barometer = BarometerSensor();
  final StepCountSensor _steps = StepCountSensor();
  final PedestrianStatusSensor _pedestrianStatus = PedestrianStatusSensor();
  final LocationSensor _location = LocationSensor();
  final CompassSensor _compass = CompassSensor();
  final WifiScanSensor _wifi = WifiScanSensor();
  final BluetoothScanSensor _bluetooth = BluetoothScanSensor();
  final ArPoseSensor _arPose = ArPoseSensor();

  // Latest values for display. Attaching one keeps its sensor running.
  late final LiveSample _accelerometerLive = LiveSample(onError: _onError);
  late final LiveSample _gyroscopeLive = LiveSample(onError: _onError);
  late final LiveSample _magnetometerLive = LiveSample(onError: _onError);
  late final LiveSample _barometerLive = LiveSample(onError: _onError);
  late final LiveSample _stepsLive = LiveSample(onError: _onError);
  late final LiveSample _pedestrianStatusLive = LiveSample(onError: _onError);
  late final LiveSample _locationLive = LiveSample(onError: _onError);
  late final LiveSample _compassLive = LiveSample(onError: _onError);
  late final LiveScan _wifiLive = LiveScan(onError: _onError);
  late final LiveScan _bluetoothLive = LiveScan(onError: _onError);
  late final LiveSample _arPoseLive = LiveSample(onError: _onError);

  /// The sensors that are running and get recorded.
  final Set<Sensor> _activeSensors = <Sensor>{};

  // Activity / pedometer
  String _activityPermissionStatus = "unknown";
  bool _hasActivityPermission = false;

  bool _hasLocationPermission = false;
  bool _hasCameraPermission = false;
  bool _hasStoragePermission = false;
  bool _hasBluetoothPermission = false;

  /// The list of errors that have occurred since the app was started
  final List<AppError> _errors = <AppError>[];

  Recorder? _recorder;
  bool _isSendingData = false;
  bool _transferImages = true;
  String? _sendStatusMessage;

  /// The PC receiver, reached over USB through `adb reverse`.
  static const String _receiverHost = "127.0.0.1";

  bool _streamLive = true;
  ConnectionStatus _streamingStatus = ConnectionStatus.disconnected;

  bool get _isRecording => _recorder != null;

  void _addError(String message) {
    if (!mounted) return;
    setState(() => _errors.insert(0, AppError(message)));
  }

  void _onError(Object error) => _addError(error.toString());

  void _dismissError(AppError error) {
    if (!mounted) return;
    setState(() => _errors.removeWhere((AppError e) => e.id == error.id));
  }

  void _clearAllErrors() {
    if (!mounted) return;
    setState(() => _errors.clear());
  }

  @override
  void initState() {
    super.initState();
    _permissionService = PermissionService();
    _cameraService = CameraService();

    _cameraService.onError = _addError;

    _initialize();
  }

  Future<void> _initialize() async {
    await _requestStoragePermission();
    await _requestActivityPermission();
    await _requestLocationPermission();
    await _requestCameraPermission();
    await _requestBluetoothPermission();
    await _startSensorListening();
  }

  /// Starts [sensor], shows its values in [live] and records it from now on.
  Future<void> _activate(Sensor sensor, LiveSample live) async {
    if (_activeSensors.contains(sensor)) return;
    _activeSensors.add(sensor);
    await live.attach(sensor);
  }

  Future<void> _requestStoragePermission() async {
    bool granted = await _permissionService.requestStoragePermission();
    if (!mounted) return;
    setState(() => _hasStoragePermission = granted);
  }

  Future<void> _requestActivityPermission() async {
    PermissionStatus status = await _permissionService
        .requestActivityPermission();
    if (!mounted) {
      return;
    }
    setState(() {
      _activityPermissionStatus = status.name;
      _hasActivityPermission = _permissionService.isActivityPermissionGranted();
    });
  }

  Future<void> _requestLocationPermission() async {
    bool granted = await _permissionService.requestLocationPermission();
    if (!mounted) {
      return;
    }
    setState(() => _hasLocationPermission = granted);
    if (!_permissionService.locationServiceEnabled) {
      _addError(
        "Device location service is disabled. "
        "Please enable it in system settings.",
      );
    } else if (!granted) {
      _addError("Location permission required for GPS tracking.");
    }

    if (granted) {
      await _activate(_location, _locationLive);
    }
  }

  Future<void> _requestBluetoothPermission() async {
    PermissionStatus status = await _permissionService
        .requestBluetoothPermission();
    if (!mounted) return;
    setState(() => _hasBluetoothPermission = status.isGranted);
  }

  Future<void> _requestCameraPermission() async {
    PermissionStatus status = await _permissionService
        .requestCameraPermission();
    if (!mounted) return;
    setState(() => _hasCameraPermission = status.isGranted);
    if (!status.isGranted) {
      _addError("Camera permission required for image capture.");
    }

    if (_hasCameraPermission) {
      // Just enumerates cameras; the primary camera is opened as part of
      // startSession() below, shared with ARCore via ARCore's SharedCamera
      // API so both can run at once.
      await _cameraService.loadCameras();
    }
  }

  Future<void> _startSensorListening() async {
    await _activate(_accelerometer, _accelerometerLive);
    await _activate(_gyroscope, _gyroscopeLive);
    await _activate(_magnetometer, _magnetometerLive);
    await _activate(_barometer, _barometerLive);
    await _activate(_compass, _compassLive);

    if (Platform.isAndroid && _hasLocationPermission) {
      await _activate(_wifi, _wifiLive);
    }
    if (_hasBluetoothPermission) {
      await _activate(_bluetooth, _bluetoothLive);
    }

    if (!_hasActivityPermission) {
      _addError("Activity permission required for pedometer.");
    } else {
      await _activate(_steps, _stepsLive);
      await _activate(_pedestrianStatus, _pedestrianStatusLive);
    }
    // Location is started inside _requestLocationPermission after the
    // geolocator permission flow completes.

    // startSession() opens the primary camera itself (shared with ARCore via
    // SharedCamera) and reports back which camera id it resolved to, since
    // that may differ from CameraService's own guess.
    String? cameraId = await _arPose.startSession();
    if (cameraId != null) {
      _cameraService.activeCameraIds = <String>{cameraId};
      await _activate(_arPose, _arPoseLive);
    }
  }

  void _resetSessionSteps() => _steps.resetSession();

  /// Called when the user taps the "Start/Stop Recording" button. If recording
  /// is being stopped, this also sends the data to the Pi and blocks until the
  /// transfer is complete.
  Future<void> _toggleRecording() async {
    Recorder? recorder = _recorder;
    Directory logsDir = await getLogsDirectory();
    if (recorder != null) {
      await _cameraService.stopCapturing();
      await recorder.dispose();
      await writeImagesCsv(logsDir);
      setState(() => _recorder = null);
      await _sendRecordedData();
    } else {
      // Sensor errors are already reported by the live displays, so the
      // recorder's error stream is not listened to here.
      recorder = Recorder(
        sensors: _activeSensors.toList(),
        sinks: <SampleSink>[
          CsvSink(logsDir),
          if (_streamLive)
            TcpStreamSink(
              host: _receiverHost,
              onStatusChange: (ConnectionStatus status) {
                if (mounted) {
                  setState(() => _streamingStatus = status);
                }
              },
            ),
        ],
      );
      await recorder.start();
      await _cameraService.startCapturing();
      setState(() => _recorder = recorder);
    }
  }

  /// Sends whatever is currently sitting in the sensor_logs directory,
  /// either just-finished recording, or an earlier recording that was made while
  /// the phone wasn't connected to a PC yet.
  Future<void> _sendRecordedData() async {
    setState(() {
      _isSendingData = true;
      _sendStatusMessage = "Starting…";
    });
    //TODO: Add a way to keep the screen on while sending, so the phone doesn't go to sleep mid-transfer.
    try {
      await uploadDirectory(
        await getLogsDirectory(),
        host: _receiverHost,
        include: (String path) =>
            _transferImages || !path.startsWith("images/"),
        onStatus: (String message) {
          if (mounted) {
            setState(() => _sendStatusMessage = message);
          }
        },
      );
    } on SocketException catch (_) {
      _addError(
        "Could not reach the PC on port 5000. Make sure receiver.py "
        "is running on the PC and the phone is connected via USB.",
      );
    } on TimeoutException catch (_) {
      _addError(
        "Timed out waiting for the PC. Make sure receiver.py is "
        "running and the phone stays connected during the transfer.",
      );
    } on UploadException catch (e) {
      _addError(e.message);
    } catch (e) {
      _addError("Failed to send data: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isSendingData = false;
          _sendStatusMessage = null;
        });
      }
    }
  }

  @override
  Future<void> dispose() async {
    for (LiveSample live in <LiveSample>[
      _accelerometerLive,
      _gyroscopeLive,
      _magnetometerLive,
      _barometerLive,
      _stepsLive,
      _pedestrianStatusLive,
      _locationLive,
      _compassLive,
      _wifiLive,
      _bluetoothLive,
      _arPoseLive,
    ]) {
      live.dispose();
    }
    await _recorder?.dispose();
    _cameraService.dispose();
    await _arPose.stopSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    // Block the back gesture/button from exiting the app mid-transfer, so
    // the user can't accidentally kill the connection while sending.
    canPop: !_isSendingData,
    child: Scaffold(
      appBar: AppBar(title: const Text("Sensor Host")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          SensorCard(
            title: "Accelerometer (m/s²)",
            tick: _accelerometerLive,
            buildReadings: () => <String>[
              "X: ${_accelerometerLive.number("acc_x")}",
              "Y: ${_accelerometerLive.number("acc_y")}",
              "Z: ${_accelerometerLive.number("acc_z")}",
            ],
          ),
          const SizedBox(height: 12),
          SensorCard(
            title: "Gyroscope (rad/s)",
            tick: _gyroscopeLive,
            buildReadings: () => <String>[
              "X: ${_gyroscopeLive.number("gyro_x")}",
              "Y: ${_gyroscopeLive.number("gyro_y")}",
              "Z: ${_gyroscopeLive.number("gyro_z")}",
            ],
          ),
          const SizedBox(height: 12),
          SensorCard(
            title: "Magnetometer (µT)",
            tick: _magnetometerLive,
            buildReadings: () => <String>[
              "X: ${_magnetometerLive.number("mag_x")}",
              "Y: ${_magnetometerLive.number("mag_y")}",
              "Z: ${_magnetometerLive.number("mag_z")}",
            ],
          ),
          const SizedBox(height: 12),
          SensorCard(
            title: "Barometer",
            tick: _barometerLive,
            buildReadings: () => <String>[
              "Pressure: ${_barometerLive.number("bar")} hPa",
            ],
          ),
          const SizedBox(height: 12),

          SensorCard(
            title: "Pedometer",
            tick: Listenable.merge(<Listenable>[
              _stepsLive,
              _pedestrianStatusLive,
            ]),
            buildReadings: () => <String>[
              "Session Steps: ${_stepsLive.text("step_session")}",
              "Total Steps:   ${_stepsLive.text("step_total")}",
              "Status:        "
                  "${_pedestrianStatusLive.text("pedometer_status")}",
              "Permission:    $_activityPermissionStatus",
            ],
            footer: ElevatedButton(
              onPressed: _resetSessionSteps,
              child: const Text("Reset Session Steps"),
            ),
          ),
          const SizedBox(height: 12),

          SensorCard(
            title: "Location (GPS)",
            tick: _locationLive,
            buildReadings: () => <String>[
              "Latitude:   ${_locationLive.number("gps_lat", decimals: 8)}",
              "Longitude:  ${_locationLive.number("gps_lon", decimals: 8)}",
              "Altitude:   ${_locationLive.number("gps_alt")} m",
              "Accuracy:   ${_locationLive.number("gps_accuracy")} m",
              "Speed:      ${_locationLive.number("gps_speed")} m/s",
              "Heading:    ${_locationLive.number("gps_heading")}°",
              "Permission: ${_permissionService.locationPermissionStatus}",
            ],
          ),
          const SizedBox(height: 12),

          SensorCard(
            title: "Compass",
            tick: _compassLive,
            buildReadings: () => <String>[
              "Heading: ${_compassLive.number("com")}°",
            ],
          ),
          const SizedBox(height: 12),

          SensorCard(
            title: "WiFi Scan",
            tick: _wifiLive,
            buildReadings: () => <String>[
              if (!Platform.isAndroid)
                "Not supported on this platform"
              else if (_wifiLive.items.isEmpty)
                "No scan results yet"
              else
                for (SensorSample ap in _wifiLive.items)
                  "${ap.values["wifi_name_list"]}: "
                      "${ap.values["wifi_sig_strength"]} dBm",
            ],
          ),
          const SizedBox(height: 12),

          SensorCard(
            title: "Bluetooth Scan (BLE)",
            tick: _bluetoothLive,
            buildReadings: () => <String>[
              if (_bluetoothLive.items.isEmpty)
                "No devices found yet"
              else
                for (SensorSample device in _bluetoothLive.items)
                  "${_nameOrUnknown(device.values["bt_name"])} "
                      "[${device.values["bt_id"]}]: "
                      "${device.values["bt_rssi"]} dBm",
            ],
          ),
          const SizedBox(height: 12),

          SensorCard(
            title: "Camera",
            buildReadings: () => <String>[
              "Cameras:    ${_cameraService.availableCameras.length}",
              "Active:     ${_cameraService.activeCameraIds.length}",
              "Permission: ${_permissionService.cameraPermissionStatus}",
              if (!_isRecording) "Capture:    idle",
            ],
          ),
          const SizedBox(height: 12),

          SensorCard(
            title: "ARCore Pose (6DOF)",
            tick: _arPoseLive,
            buildReadings: () => <String>[
              "X: ${_arPoseLive.number("ar_tx", decimals: 3)} m  "
                  "Y: ${_arPoseLive.number("ar_ty", decimals: 3)} m  "
                  "Z: ${_arPoseLive.number("ar_tz", decimals: 3)} m",
              "Tracking: ${_arPoseLive.value == null //
                      ? "STOPPED" : _arPoseLive.text("ar_tracking")}",
            ],
          ),
          const SizedBox(height: 12),

          ErrorSummaryBanner(
            errors: _errors,
            onDismiss: _dismissError,
            onClearAll: _clearAllErrors,
          ),

          RecordingControls(
            isRecording: _isRecording,
            isSendingData: _isSendingData,
            streamLive: _streamLive,
            transferImages: _transferImages,
            streamingStatus: _streamingStatus,
            sendStatusMessage: _sendStatusMessage,
            onToggleRecording: _toggleRecording,
            onSendLastData: _sendRecordedData,
            onStreamLiveChanged: (bool v) => setState(() => _streamLive = v),
            onTransferImagesChanged: (bool v) =>
                setState(() => _transferImages = v),
          ),

          PermissionButtons(
            hasStoragePermission: _hasStoragePermission,
            hasActivityPermission: _hasActivityPermission,
            hasLocationPermission: _hasLocationPermission,
            hasCameraPermission: _hasCameraPermission,
            hasBluetoothPermission: _hasBluetoothPermission,
            onRequestStorage: _requestStoragePermission,
            onRequestActivity: _requestActivityPermission,
            onRequestLocation: _requestLocationPermission,
            onRequestCamera: _requestCameraPermission,
            onRequestBluetooth: _requestBluetoothPermission,
          ),
        ],
      ),
    ),
  );

  static String _nameOrUnknown(Object? name) =>
      name == null || name == "" ? "<unknown>" : name.toString();
}
