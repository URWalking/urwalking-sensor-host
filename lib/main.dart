import "dart:async";
import "dart:io";

import "package:flutter/material.dart";
import "package:permission_handler_platform_interface/permission_handler_platform_interface.dart";
import "package:urwalking_sensor_host/services/bluetooth_service.dart";
import "package:urwalking_sensor_host/services/camera_service.dart";
import "package:urwalking_sensor_host/services/sendDataToPi.dart";
import "package:urwalking_sensor_host/services/permission.dart";
import "package:urwalking_sensor_host/services/sensors.dart";
import "package:urwalking_sensor_host/services/streaming_service.dart";
import "package:urwalking_sensor_host/widgets/error_list.dart";
import "package:urwalking_sensor_host/widgets/format_utils.dart";
import "package:urwalking_sensor_host/widgets/permission_buttons.dart";
import "package:urwalking_sensor_host/widgets/recording_controls.dart";
import "package:urwalking_sensor_host/widgets/sensor_card.dart";
import "package:wifi_scan/wifi_scan.dart";

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
  late SensorService _sensorService;
  late PermissionService _permissionService;
  late CameraService _cameraService;

  // Activity / pedometer
  String _activityPermissionStatus = "unknown";
  bool _hasActivityPermission = false;

  bool _hasLocationPermission = false;
  bool _hasCameraPermission = false;
  bool _hasStoragePermission = false;
  bool _hasBluetoothPermission = false;

  /// The list of errors that have occurred since the app was started
  final List<AppError> _errors = <AppError>[];

  bool _isRecording = false;
  bool _isSendingData = false;
  bool _transferImages = true;
  String? _sendStatusMessage;

  late StreamingService _streamingService;
  bool _streamTimestamps = true;
  StreamingStatus _streamingStatus = StreamingStatus.disconnected;

  // Each sensor has its own ValueNotifier that increments once per raw update
  final ValueNotifier<int> _accelTick = ValueNotifier<int>(0);
  final ValueNotifier<int> _gyroTick = ValueNotifier<int>(0);
  final ValueNotifier<int> _magnetometerTick = ValueNotifier<int>(0);
  final ValueNotifier<int> _barometerTick = ValueNotifier<int>(0);
  final ValueNotifier<int> _pedometerTick = ValueNotifier<int>(0);
  final ValueNotifier<int> _locationTick = ValueNotifier<int>(0);
  final ValueNotifier<int> _compassTick = ValueNotifier<int>(0);
  final ValueNotifier<int> _wifiTick = ValueNotifier<int>(0);
  final ValueNotifier<int> _bluetoothTick = ValueNotifier<int>(0);
  final ValueNotifier<int> _arPoseTick = ValueNotifier<int>(0);

  void _addError(String message) {
    if (!mounted) return;
    setState(() => _errors.insert(0, AppError(message)));
  }

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
    _sensorService = SensorService();
    _permissionService = PermissionService();
    _cameraService = CameraService();
    _cameraService.sensorService = _sensorService;

    _cameraService.onError = _addError;

    _streamingService = StreamingService();
    _streamingService.onStatusChange = (StreamingStatus status) {
      if (!mounted) return;
      setState(() => _streamingStatus = status);
    };

    _sensorService.onArPoseUpdate =
        (double tx, double ty, double tz, String state) {
          if (!mounted) return;
          _arPoseTick.value++;
        };

    _setupSensorCallbacks();
    _initialize();
  }

  void _setupSensorCallbacks() {
    _sensorService.onAccelerometerUpdate = (double x, double y, double z) {
      if (!mounted) return;
      _accelTick.value++;
    };

    _sensorService.onGyroscopeUpdate = (double x, double y, double z) {
      if (!mounted) return;
      _gyroTick.value++;
    };

    _sensorService.onMagnetometerUpdate = (double x, double y, double z) {
      if (!mounted) return;
      _magnetometerTick.value++;
    };

    _sensorService.onBarometerUpdate = (double pressure) {
      if (!mounted) return;
      _barometerTick.value++;
    };

    _sensorService.onPedometerUpdate = (int total, int session) {
      if (!mounted) return;
      _pedometerTick.value++;
    };

    _sensorService.onStatusUpdate = (String status) {
      if (!mounted) return;
      _pedometerTick.value++;
    };

    _sensorService.onLocationUpdate =
        (
          double lat,
          double lon,
          double? alt,
          double? accuracy,
          double? speed,
          double? heading,
        ) {
          if (!mounted) return;
          _locationTick.value++;
        };

    _sensorService.onLocationServiceStatusUpdate = (bool enabled) {
      if (!mounted) return;
      _locationTick.value++;
    };

    _sensorService.onCompassUpdate = (double? heading) {
      if (!mounted) return;
      _compassTick.value++;
    };

    _sensorService.onWifiScanUpdate = (List<WiFiAccessPoint> aps) {
      if (!mounted) return;
      _wifiTick.value++;
    };

    _sensorService.onBluetoothScanUpdate = (List<BtDevice> devices) {
      if (!mounted) return;
      _bluetoothTick.value++;
    };

    _sensorService.onError = _addError;

    _sensorService.shouldRecord = () => _isRecording;
  }

  Future<void> _initialize() async {
    await _requestStoragePermission();
    await _requestActivityPermission();
    await _requestLocationPermission();
    await _requestCameraPermission();
    await _requestBluetoothPermission();
    _startSensorListening();
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
      _sensorService.startLocation();
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
      // startArPose() below, shared with ARCore via ARCore's SharedCamera
      // API so both can run at once.
      await _cameraService.loadCameras();
    }
  }

  void _startSensorListening() {
    _sensorService
      ..startAccelerometer()
      ..startGyroscope()
      ..startMagnetometer()
      ..startBarometer()
      ..startCompass()
      ..startWifi()
      ..startBluetooth();

    if (!_hasActivityPermission) {
      _addError("Activity permission required for pedometer.");
    } else {
      _sensorService.startPedometer();
    }
    // Location is started inside _requestLocationPermission after the
    // geolocator permission flow completes.
    // startArPose() opens the primary camera itself (shared with ARCore via
    // SharedCamera) and reports back which camera id it resolved to, since
    // that may differ from CameraService's own guess.
    _sensorService.startArPose().then((String? cameraId) {
      if (cameraId != null) {
        _cameraService.activeCameraIds = <String>{cameraId};
      }
    });
  }

  void _resetSessionSteps() {
    setState(() {
      _sensorService.resetSessionSteps();
    });
  }

  /// Called when the user taps the "Start/Stop Recording" button. If recording
  /// is being stopped, this also sends the data to the Pi and blocks until the
  /// transfer is complete.
  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _cameraService.stopCapturing();
      await _sensorService.finalizeRecording();
      if (_streamTimestamps) {
        await _streamingService.stop();
      }
      setState(() => _isRecording = false);
      await _sendRecordedData();
    } else {
      await _sensorService.clearPreviousCsvFiles();
      _cameraService.sensorService = _sensorService;
      await _cameraService.startCapturing();
      if (_streamTimestamps) {
        await _streamingService.start();
      }
      setState(() => _isRecording = true);
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
      await sendDataToPi(
        "127.0.0.1",
        includeImages: _transferImages,
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
    _accelTick.dispose();
    _gyroTick.dispose();
    _magnetometerTick.dispose();
    _barometerTick.dispose();
    _pedometerTick.dispose();
    _locationTick.dispose();
    _compassTick.dispose();
    _wifiTick.dispose();
    _bluetoothTick.dispose();
    _arPoseTick.dispose();
    await _streamingService.dispose();
    _cameraService.dispose();
    await _sensorService.dispose();
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
            tick: _accelTick,
            buildReadings: () => <String>[
              "X: ${formatValue(_sensorService.accelX)}",
              "Y: ${formatValue(_sensorService.accelY)}",
              "Z: ${formatValue(_sensorService.accelZ)}",
            ],
          ),
          const SizedBox(height: 12),
          SensorCard(
            title: "Gyroscope (rad/s)",
            tick: _gyroTick,
            buildReadings: () => <String>[
              "X: ${formatValue(_sensorService.gyroX)}",
              "Y: ${formatValue(_sensorService.gyroY)}",
              "Z: ${formatValue(_sensorService.gyroZ)}",
            ],
          ),
          const SizedBox(height: 12),
          SensorCard(
            title: "Magnetometer (µT)",
            tick: _magnetometerTick,
            buildReadings: () => <String>[
              "X: ${formatValue(_sensorService.magnetometerX)}",
              "Y: ${formatValue(_sensorService.magnetometerY)}",
              "Z: ${formatValue(_sensorService.magnetometerZ)}",
            ],
          ),
          const SizedBox(height: 12),
          SensorCard(
            title: "Barometer",
            tick: _barometerTick,
            buildReadings: () => <String>[
              "Pressure: ${formatValue(_sensorService.barometerPressure)} hPa",
            ],
          ),
          const SizedBox(height: 12),

          SensorCard(
            title: "Pedometer",
            tick: _pedometerTick,
            buildReadings: () => <String>[
              "Session Steps: ${_sensorService.sessionSteps}",
              "Total Steps:   ${_sensorService.totalSteps}",
              "Status:        ${_sensorService.pedometerStatus}",
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
            tick: _locationTick,
            buildReadings: () => <String>[
              "Latitude:   "
                  "${formatOptional(_sensorService.locationLatitude, decimals: 8)}",
              "Longitude:  "
                  "${formatOptional(_sensorService.locationLongitude, decimals: 8)}",
              "Altitude:   ${formatOptional(_sensorService.locationAltitude)} m",
              "Accuracy:   ${formatOptional(_sensorService.locationAccuracy)} m",
              "Speed:      ${formatOptional(_sensorService.locationSpeed)} m/s",
              "Heading:    ${formatOptional(_sensorService.locationHeading)}°",
              "Stream:     ${_sensorService.locationStatus}",
              "Permission: ${_permissionService.locationPermissionStatus}",
            ],
          ),
          const SizedBox(height: 12),

          SensorCard(
            title: "Compass",
            tick: _compassTick,
            buildReadings: () => <String>[
              "Heading: ${formatOptional(_sensorService.compassHeading)}°",
            ],
          ),
          const SizedBox(height: 12),

          SensorCard(
            title: "WiFi Scan",
            tick: _wifiTick,
            buildReadings: () => <String>[
              if (_sensorService.wifiAccessPoints.isEmpty)
                "No scan results yet"
              else
                ..._sensorService.wifiAccessPoints.map(
                  (WiFiAccessPoint ap) =>
                      "${ap.ssid.isNotEmpty ? ap.ssid : '<hidden>'}: ${ap.level} dBm",
                ),
            ],
          ),
          const SizedBox(height: 12),

          SensorCard(
            title: "Bluetooth Scan (BLE)",
            tick: _bluetoothTick,
            buildReadings: () => <String>[
              if (_sensorService.bluetoothDevices.isEmpty)
                "No devices found yet"
              else
                ..._sensorService.bluetoothDevices.map(
                  (BtDevice d) =>
                      "${d.name.isNotEmpty ? d.name : '<unknown>'} [${d.id}]: ${d.rssi} dBm",
                ),
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
            tick: _arPoseTick,
            buildReadings: () => <String>[
              "X: ${_sensorService.arTx.toStringAsFixed(3)} m  "
                  "Y: ${_sensorService.arTy.toStringAsFixed(3)} m  "
                  "Z: ${_sensorService.arTz.toStringAsFixed(3)} m",
              "Tracking: ${_sensorService.arTrackingState}",
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
            streamTimestamps: _streamTimestamps,
            transferImages: _transferImages,
            streamingStatus: _streamingStatus,
            sendStatusMessage: _sendStatusMessage,
            onToggleRecording: _toggleRecording,
            onSendLastData: _sendRecordedData,
            onStreamTimestampsChanged: (bool v) =>
                setState(() => _streamTimestamps = v),
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
}
