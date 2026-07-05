import "dart:io";

import "package:flutter/services.dart";

const MethodChannel _storageChannel =
    MethodChannel("com.example.urwalking_sensor_host/camera");

/// Returns the directory where sensor logs should be saved.
Future<Directory> getLogsDirectory() async {
  String downloadsPath =
      await _storageChannel.invokeMethod<String>("getDownloadsPath")
      ?? "/storage/emulated/0/Download";
  Directory logsDir = Directory("$downloadsPath/URWalking/sensor_logs");
  await logsDir.create(recursive: true);
  return logsDir;
}
