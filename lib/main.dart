import "package:flutter/material.dart";
import "package:permission_handler/permission_handler.dart";

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
  String _permissionStatus = "unknown";
  bool _hasActivityPermission = false;
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
    _startSensorListening();
  }

  Future<void> _requestActivityPermission() async {
    PermissionStatus status = await _permissionService
        .requestActivityPermission();

    if (!mounted) {
      return;
    }
    setState(() {
      _permissionStatus = status.name;
      _hasActivityPermission = _permissionService.isActivityPermissionGranted();
    });

    // If permission was granted, retry starting pedometer
    if (_hasActivityPermission) {
      _sensorService.startPedometer();
    }
  }

  void _startSensorListening() {
    _sensorService
      ..startAccelerometer()
      ..startGyroscope()
      ..startMagnetometer()
      ..startBarometer();

    if (!_hasActivityPermission) {
      setState(() {
        _errorMessage = "Activity permission required for pedometer";
      });
    } else {
      _sensorService.startPedometer();
    }
  }

  void _resetSessionSteps() {
    setState(() {
      _sensorService.resetSessionSteps();
    });
  }

  void _toggleRecording() {
    setState(() {
      _isRecording = !_isRecording;
    });

    // If recording was stopped, finalize and save with interpolation
    if (!_isRecording) {
      _sensorService.finalizeRecording();
    }
  }

  String _formatValue(double value) => value.toStringAsFixed(2);

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
  void dispose() {
    _sensorService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text("Sensor Host")),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
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
        _buildSensorSection("Magnetometer (uT)", <String>[
          "X: ${_formatValue(_sensorService.magnetometerX)}",
          "Y: ${_formatValue(_sensorService.magnetometerY)}",
          "Z: ${_formatValue(_sensorService.magnetometerZ)}",
        ]),
        const SizedBox(height: 12),
        _buildSensorSection("Barometer", <String>[
          "Pressure: ${_formatValue(_sensorService.barometerPressure)}",
        ]),
        const SizedBox(height: 12),
        _buildSensorSection("Pedometer", <String>[
          "Session Steps: ${_sensorService.sessionSteps}",
          "Total Steps: ${_sensorService.totalSteps}",
          "Status: ${_sensorService.pedometerStatus}",
          "Permission: $_permissionStatus",
        ]),
        const SizedBox(height: 12),
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
