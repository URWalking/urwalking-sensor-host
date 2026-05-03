import "dart:async";
import "dart:io";

import "package:path_provider/path_provider.dart";

// On android run:
// adb exec-out run-as com.example.urwalking_sensor_host tar -cf - -C /data/user/0/com.example.urwalking_sensor_host/app_flutter sensor_logs | tar -xf -
// This command saves the csv files to the sensor_logs directory in this project
// Not possible to see the files directly on the device, restricted by Android for security/privacy reasons.

final Map<String, DateTime?> _lastTimestampBySensor = <String, DateTime?>{};
final Map<String, Future<void>> _writeQueueBySensor = <String, Future<void>>{};

Future<void> saveSensorSample({
  required String sensorName,
  required Map<String, String> values,
  DateTime? timestamp,
}) {
  DateTime sensorTimestamp = (timestamp ?? DateTime.now()).toLocal();
  Future<void> previousWrite =
      _writeQueueBySensor[sensorName] ?? Future<void>.value();

  Future<void> queuedWrite = previousWrite.then(
    (_) => _writeSensorSample(
      sensorName: sensorName,
      values: values,
      timestamp: sensorTimestamp,
    ),
  );

  _writeQueueBySensor[sensorName] = queuedWrite.catchError((Object error) {
    // ignore: avoid_print
    print("[CSV ERROR] $sensorName: $error");
  });
  return queuedWrite;
}

Future<void> _writeSensorSample({
  required String sensorName,
  required Map<String, String> values,
  required DateTime timestamp,
}) async {
  try {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    // ignore: avoid_print
    print("[CSV] Documents dir: ${documentsDirectory.path}");

    Directory logsDirectory = Directory(
      "${documentsDirectory.path}${Platform.pathSeparator}sensor_logs",
    );
    await logsDirectory.create(recursive: true);
    // ignore: avoid_print
    print("[CSV] Logs dir created: ${logsDirectory.path}");

    File csvFile = File(
      "${logsDirectory.path}${Platform.pathSeparator}${_csvFileName(sensorName)}",
    );
    // ignore: avoid_print
    print("[CSV] CSV file: ${csvFile.path}");

    bool needsHeader = !csvFile.existsSync() || csvFile.lengthSync() == 0;
    StringBuffer buffer = StringBuffer();

    if (needsHeader) {
      buffer.writeln(
        <String>["timestamp", "delta_ms", ...values.keys].join(","),
      );
    }

    DateTime? lastTimestamp = _lastTimestampBySensor[sensorName];
    String deltaMs = lastTimestamp == null
        ? ""
        : timestamp.difference(lastTimestamp).inMilliseconds.toString();
    _lastTimestampBySensor[sensorName] = timestamp;

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
    // ignore: avoid_print
    print("[CSV] Wrote to $sensorName successfully");
  } catch (e) {
    // ignore: avoid_print
    print("[CSV EXCEPTION] $e");
    rethrow;
  }
}

String _csvFileName(String sensorName) {
  String normalized = sensorName.toLowerCase().replaceAll(
    RegExp("[^a-z0-9]+"),
    "_",
  );
  return "$normalized.csv";
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
