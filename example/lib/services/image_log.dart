import "dart:io";

/// Converts the frame log written by the native capture pipeline
/// (`images/image_timestamps.csv`) into `images_raw.csv` next to the sensor
/// CSVs, so the PC receiver combines frames with the other sensors.
///
/// Does nothing if no frames were captured.
Future<void> writeImagesCsv(Directory logsDir) async {
  String separator = Platform.pathSeparator;
  File frameLog = File(
    "${logsDir.path}${separator}images${separator}image_timestamps.csv",
  );
  if (!frameLog.existsSync()) {
    return;
  }
  StringBuffer csv = StringBuffer()..writeln("phone_ts_ms,img_file");
  for (String line in (await frameLog.readAsLines()).skip(1)) {
    List<String> parts = line.split(",");
    if (parts.length >= 2 && int.tryParse(parts[0].trim()) != null) {
      csv.writeln("${parts[0].trim()},${parts[1].trim()}");
    }
  }
  await File(
    "${logsDir.path}${separator}images_raw.csv",
  ).writeAsString(csv.toString(), flush: true);
}
