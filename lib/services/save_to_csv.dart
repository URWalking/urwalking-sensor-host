import "dart:async";
import "dart:io";
import "package:flutter/widgets.dart";
import "package:urwalking_sensor_host/services/storage_utils.dart";

// Files are saved to the public Downloads folder (visible in file manager):
// /storage/emulated/0/Download/URWalking/sensor_logs/

final Map<String, DateTime?> _lastTimestampBySensorRaw = <String, DateTime?>{};
final Map<String, DateTime?> _lastTimestampBySensorInterpolated =
    <String, DateTime?>{};
final Map<String, Future<void>> _writeQueueBySensor = <String, Future<void>>{};

Future<void> saveSensorSample({
  required String sensorName,
  required Map<String, String> values,
  DateTime? timestamp,
  bool isInterpolated = false,
  String fileType = "interpolated",
}) {
  DateTime sensorTimestamp = (timestamp ?? DateTime.now()).toLocal();
  String queueKey = "$sensorName-$fileType";
  Future<void> previousWrite =
      _writeQueueBySensor[queueKey] ?? Future<void>.value();

  Future<void> queuedWrite = previousWrite.then(
    (_) => _writeSensorSample(
      sensorName: sensorName,
      values: values,
      timestamp: sensorTimestamp,
      isInterpolated: isInterpolated,
      fileType: fileType,
    ),
  );

  _writeQueueBySensor[queueKey] = queuedWrite.catchError((Object error) {
    debugPrint("[CSV ERROR] $sensorName ($fileType): $error");
  });
  return queuedWrite;
}

Future<void> saveSingleCsvFile({required String fileName,required String content}) async {
  try {
    Directory logsDirectory = await getLogsDirectory();
    await logsDirectory.create(recursive: true);

    File csvFile = File("${logsDirectory.path}${Platform.pathSeparator}$fileName");

    await csvFile.writeAsString(
      content,
      mode: FileMode.write,
      flush: true,
    );
    debugPrint("[CSV] Erfolgreich eine gemeinsame Datei gespeichert: ${csvFile.path}");
  } catch (e) {
    debugPrint("[CSV EXCEPTION] Fehler beim Schreiben der gemeinsamen Datei: $e");
    rethrow;
  }
}

Future<void> _writeSensorSample({
  required String sensorName,
  required Map<String, String> values,
  required DateTime timestamp,
  bool isInterpolated = false,
  String fileType = "interpolated",
}) async {
  try {
    Directory logsDirectory = await getLogsDirectory();
    debugPrint("[CSV] Logs dir: ${logsDirectory.path}");

    File csvFile = File(
      "${logsDirectory.path}${Platform.pathSeparator}${_csvFileName(sensorName, fileType)}",
    );
    debugPrint("[CSV] CSV file: ${csvFile.path}");

    bool needsHeader = !csvFile.existsSync() || csvFile.lengthSync() == 0;
    StringBuffer buffer = StringBuffer();

    if (needsHeader) {
      buffer.writeln(
        <String>["timestamp", "delta_ms", ...values.keys].join(","),
      );
    }

    final Map<String, DateTime?> timestampMap = fileType == "raw"
        ? _lastTimestampBySensorRaw
        : _lastTimestampBySensorInterpolated;
    final String sensorKey = "$sensorName-$fileType";
    DateTime? lastTimestamp = timestampMap[sensorKey];
    String deltaMs = lastTimestamp == null
        ? ""
        : timestamp.difference(lastTimestamp).inMilliseconds.toString();
    timestampMap[sensorKey] = timestamp;

    buffer.writeln(
      <String>[
        _escapeCsv(_formatTimestamp(timestamp)),
        _escapeCsv(deltaMs),
        ...values.values.map(_escapeCsv),
      ].join(","),
    );

    await csvFile.writeAsString(
      buffer.toString(),
      mode: FileMode.append,
      flush: true,
    );
    debugPrint("[CSV] Wrote to $sensorName ($fileType) successfully");
  } catch (e) {
    debugPrint("[CSV EXCEPTION] $e");
    rethrow;
  }
}

String _csvFileName(String sensorName, String fileType) {
  String normalized = sensorName.toLowerCase().replaceAll(
    RegExp("[^a-z0-9]+"),
    "_",
  );
  return "${normalized}_$fileType.csv";
}

String _formatTimestamp(DateTime timestamp) {
  DateTime localTime = timestamp.toLocal();
  String datePart =
      '${localTime.year.toString().padLeft(4, '0')}-'
      '${localTime.month.toString().padLeft(2, '0')}-'
      '${localTime.day.toString().padLeft(2, '0')}';
  String timePart =
      '${localTime.hour.toString().padLeft(2, '0')}:'
      '${localTime.minute.toString().padLeft(2, '0')}:'
      '${localTime.second.toString().padLeft(2, '0')}.'
      '${localTime.millisecond.toString().padLeft(3, '0')}';
  return "$datePart $timePart";
}

String _escapeCsv(String value) {
  if (value.contains(",") || value.contains('"') || value.contains("\n")) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
