import "package:flutter/material.dart";
import "package:permission_handler_platform_interface/permission_handler_platform_interface.dart";
import "package:urwalking_sensor_host/services/bluetooth_service.dart";
import "package:urwalking_sensor_host/services/camera_service.dart";
import "package:urwalking_sensor_host/services/sendDataToPi.dart";
import "package:urwalking_sensor_host/services/permission.dart";
import "package:urwalking_sensor_host/services/sensors.dart";
import "package:urwalking_sensor_host/services/streaming_service.dart";
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

  String? _errorMessage;
  bool _isRecording = false;

  late StreamingService _streamingService;
  bool _streamTimestamps = false;
  StreamingStatus _streamingStatus = StreamingStatus.disconnected;

  @override
  void initState() {
    super.initState();
    _sensorService = SensorService();
    _permissionService = PermissionService();
    _cameraService = CameraService();
    _cameraService.sensorService = _sensorService;

    _cameraService.onError = (String error) {
      if (!mounted) return;
      setState(() => _errorMessage = error);
    };

    _streamingService = StreamingService();
    _streamingService.onStatusChange = (StreamingStatus status) {
      if (!mounted) return;
      setState(() => _streamingStatus = status);
    };

    _sensorService.onArPoseUpdate = (
      double tx,
      double ty,
      double tz,
      String state,
    ) {
      if (!mounted) return;
      setState(() {});
    };

    _setupSensorCallbacks();
    _initialize();
  }

  void _setupSensorCallbacks() {
    _sensorService.onAccelerometerUpdate = (double x, double y, double z) {
      if (!mounted) {
        return;
      }
      setState(() {});
    };

    _sensorService.onGyroscopeUpdate = (double x, double y, double z) {
      if (!mounted) {
        return;
      }
      setState(() {});
    };

    _sensorService.onMagnetometerUpdate = (double x, double y, double z) {
      if (!mounted) {
        return;
      }
      setState(() {});
    };

    _sensorService.onBarometerUpdate = (double pressure) {
      if (!mounted) {
        return;
      }
      setState(() {});
    };

    _sensorService.onPedometerUpdate = (int total, int session) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = null;
      });
    };

    _sensorService.onStatusUpdate = (String status) {
      if (!mounted) {
        return;
      }
      setState(() {});
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
          if (!mounted) {
            return;
          }
          setState(() {
            _errorMessage = null;
          });
        };

    _sensorService.onLocationServiceStatusUpdate = (bool enabled) {
      if (!mounted) {
        return;
      }
      setState(() {});
    };

    _sensorService.onCompassUpdate = (double? heading) {
      if (!mounted) {
        return;
      }
      setState(() {});
    };

    _sensorService.onWifiScanUpdate = (List<WiFiAccessPoint> aps) {
      if (!mounted) return;
      setState(() {});
    };

    _sensorService.onBluetoothScanUpdate = (List<BtDevice> devices) {
      if (!mounted) return;
      setState(() {});
    };

    _sensorService.onError = (String error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error;
      });
    };

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
    setState(() {
      _hasLocationPermission = granted;
      if (!_permissionService.locationServiceEnabled) {
        _errorMessage =
            "Device location service is disabled. "
            "Please enable it in system settings.";
      } else if (!granted) {
        _errorMessage = "Location permission required for GPS tracking.";
      }
    });

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
    setState(() {
      _hasCameraPermission = status.isGranted;
      if (!status.isGranted) {
        _errorMessage = "Camera permission required for image capture.";
      }
    });

    if (_hasCameraPermission) {
      await _cameraService.loadCameras();
      await _cameraService.openCameras();
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
      setState(() {
        _errorMessage = "Activity permission required for pedometer.";
      });
    } else {
      _sensorService.startPedometer();
    }
    // Location is started inside _requestLocationPermission after the
    // geolocator permission flow completes.
    _sensorService.startArPose();
  }

  void _resetSessionSteps() {
    setState(() {
      _sensorService.resetSessionSteps();
    });
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _cameraService.stopCapturing();
      await _cameraService.closeAllCameras();
      await _sensorService.finalizeRecording();
      if (_streamTimestamps) {
        await _streamingService.stop();
      }
      await _sensorService.startArPose();
      setState(() => _isRecording = false);
    } else {
      await _sensorService.stopArPose();
      await _cameraService.openCameras();
      _cameraService.sensorService = _sensorService;
      await _cameraService.startCapturing();
      if (_streamTimestamps) {
        await _streamingService.start();
      }
      setState(() => _isRecording = true);
    }
  }

  String _formatValue(double value) => value.toStringAsFixed(2);

  String _formatOptional(double? value, {int decimals = 2}) =>
      value != null ? value.toStringAsFixed(decimals) : "—";

  Widget _buildSensorSection(String title, List<String> readings) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...readings.map(
            (String reading) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(reading),
            ),
          ),
        ],
      ),
    ),
  );

  @override
  Future<void> dispose() async {
    await _streamingService.dispose();
    _cameraService.dispose();
    await _sensorService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("Sensor Host")),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        // IMU
        _buildSensorSection("Accelerometer (m/s²)", <String>[
          "X: ${_formatValue(_sensorService.accelX)}",
          "Y: ${_formatValue(_sensorService.accelY)}",
          "Z: ${_formatValue(_sensorService.accelZ)}",
        ]),
        const SizedBox(height: 12),
        _buildSensorSection("Gyroscope (rad/s)", <String>[
          "X: ${_formatValue(_sensorService.gyroX)}",
          "Y: ${_formatValue(_sensorService.gyroY)}",
          "Z: ${_formatValue(_sensorService.gyroZ)}",
        ]),
        const SizedBox(height: 12),
        _buildSensorSection("Magnetometer (µT)", <String>[
          "X: ${_formatValue(_sensorService.magnetometerX)}",
          "Y: ${_formatValue(_sensorService.magnetometerY)}",
          "Z: ${_formatValue(_sensorService.magnetometerZ)}",
        ]),
        const SizedBox(height: 12),
        _buildSensorSection("Barometer", <String>[
          "Pressure: ${_formatValue(_sensorService.barometerPressure)} hPa",
        ]),
        const SizedBox(height: 12),

        // Pedometer
        _buildSensorSection("Pedometer", <String>[
          "Session Steps: ${_sensorService.sessionSteps}",
          "Total Steps:   ${_sensorService.totalSteps}",
          "Status:        ${_sensorService.pedometerStatus}",
          "Permission:    $_activityPermissionStatus",
        ]),
        const SizedBox(height: 12),

        // Location (GPS)
        _buildSensorSection("Location (GPS)", <String>[
          "Latitude:   ${_formatOptional(_sensorService.locationLatitude, decimals: 8)}",
          "Longitude:  ${_formatOptional(_sensorService.locationLongitude, decimals: 8)}",
          "Altitude:   ${_formatOptional(_sensorService.locationAltitude)} m",
          "Accuracy:   ${_formatOptional(_sensorService.locationAccuracy)} m",
          "Speed:      ${_formatOptional(_sensorService.locationSpeed)} m/s",
          "Heading:    ${_formatOptional(_sensorService.locationHeading)}°",
          "Stream:     ${_sensorService.locationStatus}",
          "Permission: ${_permissionService.locationPermissionStatus}",
        ]),
        const SizedBox(height: 12),

        // Compass
        _buildSensorSection("Compass", <String>[
          "Heading: ${_formatOptional(_sensorService.compassHeading)}°",
        ]),
        const SizedBox(height: 12),

        // WiFi
        _buildSensorSection("WiFi Scan", <String>[
          if (_sensorService.wifiAccessPoints.isEmpty)
            "No scan results yet"
          else
            ..._sensorService.wifiAccessPoints.map(
              (ap) =>
                  "${ap.ssid.isNotEmpty ? ap.ssid : '<hidden>'}: ${ap.level} dBm",
            ),
        ]),
        const SizedBox(height: 12),

        // Bluetooth
        _buildSensorSection("Bluetooth Scan (BLE)", <String>[
          if (_sensorService.bluetoothDevices.isEmpty)
            "No devices found yet"
          else
            ..._sensorService.bluetoothDevices.map(
              (BtDevice d) =>
                  "${d.name.isNotEmpty ? d.name : '<unknown>'} [${d.id}]: ${d.rssi} dBm",
            ),
        ]),
        const SizedBox(height: 12),

        // Camera
        _buildSensorSection("Camera", <String>[
          "Cameras:    ${_cameraService.availableCameras.length}",
          "Active:     ${_cameraService.activeCameraIds.length}",
          "Permission: ${_permissionService.cameraPermissionStatus}",
          if (!_isRecording) "Capture:    idle",
        ]),
        const SizedBox(height: 12),
        _buildSensorSection("ARCore Pose (6DOF)", <String>[
          "X: ${_sensorService.arTx.toStringAsFixed(3)} m  "
              "Y: ${_sensorService.arTy.toStringAsFixed(3)} m  "
              "Z: ${_sensorService.arTz.toStringAsFixed(3)} m",
          "Tracking: ${_sensorService.arTrackingState}",
        ]),
        const SizedBox(height: 12),

        // Buttons
        ElevatedButton(
          onPressed: _resetSessionSteps,
          child: const Text("Reset Session Steps"),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          title: const Text("Timestamps streamen"),
          subtitle: _isRecording && _streamTimestamps
              ? Text(_streamingStatus.name)
              : null,
          value: _streamTimestamps,
          onChanged: _isRecording
              ? null
              : (bool v) => setState(() => _streamTimestamps = v),
        ),
        ElevatedButton(
          onPressed: _toggleRecording,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isRecording ? Colors.green : Colors.grey,
          ),
          child: Text(_isRecording ? "Stop Recording" : "Start Recording"),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue.shade100,
          ),
          child: const Text("Stop&Send"),
          onPressed: () async {
            // Falls die Aufnahme noch läuft, stoppen wir zuerst die Kamera
            if (_isRecording) {
              _cameraService.stopCapturing();
              setState(() => _isRecording = false);
            }
            
            await _sensorService.finalizeRecording();
            await sendDataToPi("127.0.0.1");
          },
        ),

        if (!_hasStoragePermission) ...<Widget>[
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _requestStoragePermission,
            child: const Text("Request Storage Permission"),
          ),
        ],
        if (!_hasActivityPermission) ...<Widget>[
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _requestActivityPermission,
            child: const Text("Request Activity Permission"),
          ),
        ],
        if (!_hasLocationPermission) ...<Widget>[
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _requestLocationPermission,
            child: const Text("Request Location Permission"),
          ),
        ],
        if (!_hasCameraPermission) ...<Widget>[
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _requestCameraPermission,
            child: const Text("Request Camera Permission"),
          ),
        ],
        if (!_hasBluetoothPermission) ...<Widget>[
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _requestBluetoothPermission,
            child: const Text("Request Bluetooth Permission"),
          ),
        ],

        if (_errorMessage != null) ...<Widget>[
          const SizedBox(height: 12),
          Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                "Error: $_errorMessage",
                style: TextStyle(color: Colors.red.shade900),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}
