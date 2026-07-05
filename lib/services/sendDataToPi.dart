import "dart:io";

import "package:archive/archive_io.dart";
import "package:flutter/foundation.dart";
import "package:urwalking_sensor_host/services/storage_utils.dart";

const String _imagesPrefix = "images/";

/// Walks the logs directory at `args.$1` and tars it into bytes, skipping
/// the images folder when `args.$2` (includeImages) is false. Runs inside a
/// background isolate via [compute] — with hundreds of captured images this
/// is heavy synchronous CPU work that would otherwise freeze the UI isolate
/// for seconds, which previously caused repeated re-entrant taps on the send
/// button to pile up and never complete.
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

/// Packs the sensor_logs directory (all per-sensor CSVs, plus the images
/// folder when [includeImages] is true) into a single tar and sends it to
/// the receiver script listening on [piIpAddress]:5000. [onStatus], if
/// given, is called with short human-readable progress messages so the UI
/// can show the caller something more specific than a spinner.
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

    // Handing bytes to the local socket buffer only means the OS has them —
    // not that they've actually made it across the adb-reverse USB tunnel
    // and been extracted on the PC. Wait for the receiver's explicit
    // acknowledgment (sent only after it finishes extracting) before
    // declaring the transfer done.
    onStatus?.call("Waiting for the PC to finish…");
    List<int> ackBytes = await socket
        .fold<List<int>>(
          <int>[],
          (List<int> acc, Uint8List chunk) => acc..addAll(chunk),
        )
        .timeout(const Duration(seconds: 120));
    await socket.close();

    String ack = String.fromCharCodes(ackBytes);
    if (ack.startsWith("OK")) {
      print("[Flutter] Data successfully sent and confirmed by receiver.");
    } else {
      print("[Flutter] Receiver reported a problem: $ack");
    }
  } catch (e) {
    print("Error while sending data: $e");
    if (socket != null) {
      await socket.close();
    }
  }
}
