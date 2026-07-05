import "dart:io";

import "package:archive/archive_io.dart";
import "package:flutter/foundation.dart";
import "package:urwalking_sensor_host/services/storage_utils.dart";

const String _imagesPrefix = "images/";

/// Packs the sensor_logs directory (all per-sensor CSVs, plus the images
/// folder when [includeImages] is true) into a single tar and returns it as a
/// [Uint8List].
Uint8List _packLogsDirectory((String, bool) args) {
  final (String logsDirPath, bool includeImages) = args;
  Directory logsDir = Directory(logsDirPath);
  Archive archive = Archive();
  for (FileSystemEntity entity in logsDir.listSync(recursive: true)) {
    if (entity is File) {
      String relativePath = entity.path
          .substring(logsDirPath.length + 1)
          .replaceAll(Platform.pathSeparator, "/");
      if (!includeImages && relativePath.startsWith(_imagesPrefix)) {
        continue;
      }
      Uint8List bytes = entity.readAsBytesSync();
      archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
    }
  }
  return Uint8List.fromList(TarEncoder().encode(archive));
}

/// Sends the sensor_logs directory (all per-sensor CSVs, plus the images
/// folder when [includeImages] is true) to the Raspberry Pi at [piIpAddress] via
/// TCP on port 5000. The Pi must be running the receiver.py script to accept the data.
Future<void> sendDataToPi(
  String piIpAddress, {
  bool includeImages = true,
  void Function(String message)? onStatus,
}) async {
  Socket? socket;
  const int piPort = 5000;

  try {
    Directory logsDir = await getLogsDirectory();
    if (!await logsDir.exists()) {
      print(
        "[Flutter] Warning: logs directory does not exist, nothing to send.",
      );
      return;
    }

    onStatus?.call("Packing data…");
    print("[Flutter] Packing ${logsDir.path} into TAR archive...");
    Uint8List tarBytes = await compute(_packLogsDirectory, (
      logsDir.path,
      includeImages,
    ));
    if (tarBytes.isEmpty) {
      print("[Flutter] Error: TAR archive could not be generated.");
      return;
    }

    double mb = tarBytes.length / 1024 / 1024;
    onStatus?.call("Sending ${mb.toStringAsFixed(2)} MB…");
    print(
      "[Flutter] Connecting to $piIpAddress:$piPort and sending "
      "(${mb.toStringAsFixed(2)} MB)...",
    );
    socket = await Socket.connect(
      piIpAddress,
      piPort,
      timeout: const Duration(seconds: 10),
    );
    socket
      ..add(Uint8List(8)..buffer.asByteData().setUint64(0, tarBytes.length))
      ..add(tarBytes);
    await socket.flush();

    // Wait for the receiver to send back an "OK"
    onStatus?.call("Waiting for the PC to finish…");
    List<int> ackBytes = await socket
        .fold<List<int>>(
          <int>[],
          (List<int> acc, Uint8List chunk) => acc..addAll(chunk),
        )
        .timeout(const Duration(seconds: 120));

    String ack = String.fromCharCodes(ackBytes);
    if (ack.isEmpty) {
      throw Exception(
        "No response from the PC. Either receiver.py isn't running there, "
        "or the USB connection was interrupted mid-transfer.",
      );
    }
    if (!ack.startsWith("OK")) {
      throw Exception("Receiver reported a problem: $ack");
    }
    print("[Flutter] Data successfully sent and confirmed by receiver.");
  } finally {
    if (socket != null) {
      await socket.close();
    }
  }
}
