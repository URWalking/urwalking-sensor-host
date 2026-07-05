import "dart:io";

import "package:flutter/services.dart";
import "package:flutter/widgets.dart";
import "package:urwalking_sensor_host/services/sensors.dart";
import "package:urwalking_sensor_host/services/storage_utils.dart";

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

  static const MethodChannel _channel = MethodChannel(
    "com.example.urwalking_sensor_host/camera",
  );

  List<CameraDevice> availableCameras = <CameraDevice>[];
  Set<String> activeCameraIds = <String>{};

  Function(List<CameraDevice>)? onCamerasLoaded;
  Function(String)? onError;

  Future<void> loadCameras() async {
    try {
      Map<dynamic, dynamic> raw = await _channel.invokeMethod("listCameras");

      availableCameras = (raw["cameras"] as List<dynamic>)
          .map((cam) => CameraDevice.fromMap(cam as Map<dynamic, dynamic>))
          .toList();

      List<dynamic> concurrentSets = raw["concurrentSets"] as List<dynamic>;

      if (concurrentSets.isNotEmpty) {
        List<String> best = concurrentSets
            .map((s) => (s as List<dynamic>).cast<String>())
            .reduce((a, b) => a.length >= b.length ? a : b);
        activeCameraIds = best.toSet();
      } else {
        _fallbackCameraSelection();
      }

      // Keep only the back camera (LENS_FACING_BACK = 1)
      activeCameraIds.retainWhere((String id) {
        CameraDevice? cam = availableCameras
            .cast<CameraDevice?>()
            .firstWhere((c) => c?.id == id, orElse: () => null);
        return cam?.facing == 1;
      });

      debugPrint("CameraService: active cameras (front only): $activeCameraIds");
      onCamerasLoaded?.call(availableCameras);
    } on PlatformException catch (e) {
      onError?.call("Failed to list cameras: ${e.message}");
      _fallbackCameraSelection();
    }
  }

  void _fallbackCameraSelection() {
    CameraDevice? back = availableCameras.where((c) => c.facing == 1).firstOrNull;
    activeCameraIds = {if (back != null) back.id};
  }

  Future<void> openCameras() async {
    for (String id in activeCameraIds) {
      try {
        await _channel.invokeMethod<int>("openCamera", {"cameraId": id});
        await Future.delayed(const Duration(milliseconds: 500));
      } on PlatformException catch (e) {
        onError?.call("Failed to open camera $id: ${e.message}");
      }
    }
  }

  Future<void> startCapturing() async {
    if (activeCameraIds.isEmpty) return;
    String cameraId = activeCameraIds.first;
    Directory logsDir = await getLogsDirectory();
    Directory imagesDir = Directory("${logsDir.path}${Platform.pathSeparator}images");
    // Wipe any images left over from a previous recording so each session
    // only ever ships its own frames instead of every session's images
    // piling up forever (this is what made "Stop & Send" balloon to
    // hundreds of MB after a handful of test recordings).
    if (await imagesDir.exists()) {
      await imagesDir.delete(recursive: true);
    }
    await imagesDir.create(recursive: true);
    try {
      await _channel.invokeMethod<void>("startFastCapture", {
        "cameraId": cameraId,
        "outputDir": imagesDir.path,
      });
    } on PlatformException catch (e) {
      onError?.call("startFastCapture failed: ${e.message}");
    }
  }

  Future<void> stopCapturing() async {
    if (activeCameraIds.isEmpty) return;
    try {
      await _channel.invokeMethod<void>("stopFastCapture", {
        "cameraId": activeCameraIds.first,
      });
    } on PlatformException catch (e) {
      onError?.call("stopFastCapture failed: ${e.message}");
    }
    await _injectImageRecords();
  }

  Future<void> _injectImageRecords() async {
    if (sensorService == null) return;
    try {
      Directory logsDir = await getLogsDirectory();
      File csvFile = File(
        "${logsDir.path}${Platform.pathSeparator}images${Platform.pathSeparator}image_timestamps.csv",
      );
      if (!await csvFile.exists()) return;
      List<String> lines = await csvFile.readAsLines();
      for (String line in lines.skip(1)) {
        List<String> parts = line.split(",");
        if (parts.length < 2) continue;
        int? ts = int.tryParse(parts[0].trim());
        String filename = parts[1].trim();
        if (ts == null || filename.isEmpty) continue;
        sensorService!.addImageRecord(
          filename,
          DateTime.fromMillisecondsSinceEpoch(ts),
        );
      }
    } catch (e) {
      onError?.call("Failed to inject image records: $e");
    }
  }

  Future<void> closeAllCameras() async {
    await _channel.invokeMethod("closeCamera");
  }

  /// Keeps the screen on (or lets it sleep again), used while a data
  /// transfer is in progress so the device doesn't go to sleep mid-send.
  Future<void> setKeepScreenOn(bool on) async {
    try {
      await _channel.invokeMethod<void>("setKeepScreenOn", {"on": on});
    } on PlatformException catch (_) {
      // Best-effort; not critical if unsupported.
    }
  }

  Future<void> dispose() async {
    await stopCapturing();
    await _channel.invokeMethod("closeCamera");
  }
}
