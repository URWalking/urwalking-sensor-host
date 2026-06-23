import "dart:io";

import "package:flutter/services.dart";

// ignore_for_file: public_member_api_docs

const MethodChannel _storageChannel =
    MethodChannel("com.example.urwalking_sensor_host/camera");

Future<Directory> getLogsDirectory() async {
  String downloadsPath =
      await _storageChannel.invokeMethod<String>("getDownloadsPath")
      ?? "/storage/emulated/0/Download";
  Directory logsDir = Directory("$downloadsPath/URWalking/sensor_logs");
  await logsDir.create(recursive: true);
  return logsDir;
}
