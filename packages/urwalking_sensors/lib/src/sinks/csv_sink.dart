import "dart:io";

import "package:urwalking_sensors/src/core/sample_sink.dart";
import "package:urwalking_sensors/src/core/sensor_sample.dart";

/// Writes one CSV file per sensor into [directory].
///
/// Each sensor gets a file named `<sensor id>_raw.csv`. The first column is
/// `phone_ts_ms` (milliseconds since the Unix epoch), followed by one column
/// per value field, in the order of the sensor's first sample. This is the
/// format that `tools/receiver/data_processor.py` combines and interpolates.
///
/// Rows are streamed to disk while recording, so long recordings do not
/// have to fit into memory.
class CsvSink extends SampleSink {
  /// Creates a sink that writes into [directory].
  ///
  /// If [clearExisting] is true, [open] deletes `*_raw.csv` files left in
  /// [directory] by an earlier recording.
  CsvSink(this.directory, {this.clearExisting = true});

  /// The directory the CSV files are written to. Created if missing.
  final Directory directory;

  /// Whether [open] deletes existing `*_raw.csv` files in [directory].
  final bool clearExisting;

  final Map<String, _CsvFile> _files = <String, _CsvFile>{};

  /// The files written so far, by sensor id.
  Map<String, File> get files => <String, File>{
    for (MapEntry<String, _CsvFile> entry in _files.entries)
      entry.key: entry.value.file,
  };

  @override
  Future<void> open() async {
    await directory.create(recursive: true);
    if (!clearExisting) {
      return;
    }
    await for (FileSystemEntity entity in directory.list()) {
      if (entity is File && entity.path.endsWith("_raw.csv")) {
        await entity.delete();
      }
    }
  }

  @override
  void add(SensorSample sample) {
    _files
        .putIfAbsent(sample.sensorId, () => _CsvFile.create(directory, sample))
        .write(sample);
  }

  @override
  Future<void> close() async {
    for (_CsvFile file in _files.values) {
      await file.close();
    }
    _files.clear();
  }
}

class _CsvFile {
  _CsvFile(this.file, this.columns) : _sink = file.openWrite() {
    _sink.writeln(<String>["phone_ts_ms", ...columns].map(_escape).join(","));
  }

  factory _CsvFile.create(Directory directory, SensorSample first) => _CsvFile(
    File("${directory.path}${Platform.pathSeparator}${first.sensorId}_raw.csv"),
    first.values.keys.toList(),
  );

  final File file;
  final List<String> columns;
  final IOSink _sink;

  void write(SensorSample sample) {
    _sink.writeln(
      <String>[
        sample.timestamp.millisecondsSinceEpoch.toString(),
        for (String column in columns) _escape(_format(sample.values[column])),
      ].join(","),
    );
  }

  Future<void> close() async {
    await _sink.flush();
    await _sink.close();
  }

  static String _format(Object? value) => switch (value) {
    null => "",
    double() => value.toStringAsFixed(6),
    _ => value.toString(),
  };

  static String _escape(String value) =>
      value.contains(",") || value.contains('"') || value.contains("\n")
      ? '"${value.replaceAll('"', '""')}"'
      : value;
}
