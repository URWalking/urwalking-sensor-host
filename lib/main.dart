import "package:flutter/material.dart";
import "package:permission_handler_platform_interface/permission_handler_platform_interface.dart";

import "package:urwalking_sensor_host/services/permission.dart";
import "package:urwalking_sensor_host/services/sensors.dart";

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

  // Activity / pedometer
  String _activityPermissionStatus = "unknown";
  bool _hasActivityPermission = false;

  // Location
  bool _hasLocationPermission = false;

  String? _errorMessage;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _sensorService = SensorService();
    _permissionService = PermissionService();
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
    await _requestActivityPermission();
    await _requestLocationPermission();
    _startSensorListening();
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

  void _startSensorListening() {
    _sensorService
      ..startAccelerometer()
      ..startGyroscope()
      ..startMagnetometer()
      ..startBarometer()
      ..startCompass();

    if (!_hasActivityPermission) {
      setState(() {
        _errorMessage = "Activity permission required for pedometer.";
      });
    } else {
      _sensorService.startPedometer();
    }
    // Location is started inside _requestLocationPermission after the
    // geolocator permission flow completes.
  }

  void _resetSessionSteps() {
    setState(() {
      _sensorService.resetSessionSteps();
    });
  }

  Future<void> _toggleRecording() async {
    setState(() {
      _isRecording = !_isRecording;
    });
    if (!_isRecording) {
      await _sensorService.finalizeRecording();
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

        // Buttons
        ElevatedButton(
          onPressed: _resetSessionSteps,
          child: const Text("Reset Session Steps"),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: _toggleRecording,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isRecording ? Colors.green : Colors.grey,
          ),
          child: Text(_isRecording ? "Stop Recording" : "Start Recording"),
        ),

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
