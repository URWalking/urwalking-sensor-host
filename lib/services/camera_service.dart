import "dart:async";
import "dart:io";

import "package:flutter/services.dart";
import "package:flutter/widgets.dart";
import "package:path/path.dart";
import "package:path_provider/path_provider.dart";
import "package:urwalking_sensor_host/services/sensors.dart";

class CameraDevice {
  final String id;
  final String name;
  final int facing;

  CameraDevice({required this.id, required this.name, required this.facing});

  factory CameraDevice.fromMap(Map<dynamic, dynamic> map) => CameraDevice(
    id: map["id"] as String,
    name: map["name"] as String,
    facing: map["facing"] as int,
  );
}


class CameraService {
  SensorService? sensorService;

  // Configuration
  static const Duration captureInterval = Duration(seconds: 3);

  // Platform channel
  static const MethodChannel _channel = MethodChannel(
    "com.example.urwalking_sensor_host/camera",
  );

  // State
  List<CameraDevice> availableCameras = <CameraDevice>[];
  Set<String> activeCameraIds = <String>{};
  bool lastCaptureFlash = false;
  Timer? _captureTimer;

  // Callbacks
  Function(List<CameraDevice>)? onCamerasLoaded;
  Function()? onCaptureComplete;
  Function(String)? onError;

  // Init

  Future<void> loadCameras() async {
    try {
      Map<dynamic, dynamic> raw = await _channel.invokeMethod("listCameras");

      availableCameras = (raw["cameras"] as List<dynamic>)
          .map((cam) => CameraDevice.fromMap(cam as Map<dynamic, dynamic>))
          .toList();

      // Get the list from MainActivity.kt of sets of cameras that can be used
      List<dynamic> concurrentSets = raw["concurrentSets"] as List<dynamic>;

      if (concurrentSets.isNotEmpty) {
        // Pick the largest concurrent set, more cameras = more data.
        List<String> best = concurrentSets
            .map((s) => (s as List<dynamic>).cast<String>())
            .reduce((a, b) => a.length >= b.length ? a : b);

        activeCameraIds = best.toSet();
        debugPrint("CameraService Using concurrent set: $activeCameraIds");
      } else {
        // Fallback (option B): one back + one front.
        _fallbackCameraSelection();
      }

      onCamerasLoaded?.call(availableCameras);
    } on PlatformException catch (e) {
      onError?.call("Failed to list cameras: ${e.message}");
      // Fallback (option A): just use whatever cameras are available.
      _fallbackCameraSelection();
    }
  }

  void _fallbackCameraSelection() {
    final CameraDevice? back = availableCameras.where((c) => c.facing == 0).firstOrNull;
    final CameraDevice? front = availableCameras.where((c) => c.facing == 1).firstOrNull;
    
    activeCameraIds = {
      if (back != null) back.id,
      if (front != null) front.id,
    };
  }

  Future<void> openCameras() async {
    for (final String id in activeCameraIds) {
      try {
        await _channel.invokeMethod<int>("openCamera", {"cameraId": id});
        await Future.delayed(
          const Duration(milliseconds: 500),
        ); // match colleague's delay
      } on PlatformException catch (e) {
        onError?.call("Failed to open camera $id: ${e.message}");
      }
    }
  }

  // Recording

  void startCapturing() {
    _runCapture(); // immediate first capture
    _captureTimer = Timer.periodic(captureInterval, (_) => _runCapture());
  }

  void stopCapturing() {
    _captureTimer?.cancel();
    _captureTimer = null;
  }

  Future<void> _runCapture() async {
    if (activeCameraIds.isEmpty) return;

    final List<Future<void>> futures = activeCameraIds.map((id) async {
      try {
        final String? nativePath = await _channel.invokeMethod<String>(
          "takePicture",
          {"cameraId": id},
        );
        if (nativePath == null) return;

        final CameraDevice camera = availableCameras.firstWhere(
          (c) => c.id == id,
        );
        await _saveImage(nativePath, camera);
      } on PlatformException catch (e) {
        onError?.call("Capture failed for camera $id: ${e.message}");
      }
    }).toList();

    await Future.wait(futures);

    lastCaptureFlash = true;
    onCaptureComplete?.call();

    // Reset flash after short delay so the UI can blink
    await Future.delayed(const Duration(milliseconds: 300));
    lastCaptureFlash = false;
    onCaptureComplete?.call();
  }

  Future<void> _saveImage(String nativePath, CameraDevice camera) async {
    try {
      final Directory docs = await getApplicationDocumentsDirectory();
      final Directory imagesDir = Directory(
        "${docs.path}${Platform.pathSeparator}sensor_logs"
        "${Platform.pathSeparator}images",
      );
      await imagesDir.create(recursive: true);

      final String timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(":", "-")
          .replaceAll(".", "-");
      final String safeName = camera.name.replaceAll(RegExp(r"[^\w]"), "_");
      final String fileName =
          "${timestamp}_${safeName}_${camera.id}_${camera.facing}.jpg";

      final File source = File(nativePath);

      if (await source.exists()) {
        await source.copy("${imagesDir.path}${Platform.pathSeparator}$fileName");
        await source.delete(); 
      }

      if (sensorService != null) {
        if (camera.facing == 0) {
          sensorService!.recordImageBack(fileName);
        } else if (camera.facing == 1) {
          sensorService!.recordImageFront(fileName);
        }
      }
    } catch (e) {
      onError?.call("Failed to save image: $e");
    }
  }

  // Dispose

  Future<void> dispose() async {
    stopCapturing();
    await _channel.invokeMethod("closeCamera");
  }
}

