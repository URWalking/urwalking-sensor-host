import "dart:io";

import "package:flutter_test/flutter_test.dart";
import "package:urwalking_sensors/urwalking_sensors.dart";

SensorSample _sample(String sensorId, int ms, Map<String, Object?> values) =>
    SensorSample(
      sensorId: sensorId,
      timestamp: DateTime.fromMillisecondsSinceEpoch(ms),
      values: values,
    );

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp("csv_sink_test");
  });

  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test("writes one file per sensor in the receiver's format", () async {
    CsvSink sink = CsvSink(directory);
    await sink.open();
    sink
      ..add(
        _sample("accelerometer", 1000, <String, Object?>{
          "acc_x": 0.5,
          "acc_y": -1.0,
          "acc_z": 9.81,
        }),
      )
      ..add(
        _sample("wifi", 1001, <String, Object?>{
          "wifi_name_list": "Cafe, 2nd floor",
          "wifi_sig_strength": -70,
        }),
      )
      ..add(
        _sample("accelerometer", 1020, <String, Object?>{
          "acc_x": 0.25,
          "acc_y": null,
          "acc_z": 9.8,
        }),
      );
    Map<String, File> files = sink.files;
    await sink.close();

    expect(await files["accelerometer"]!.readAsLines(), <String>[
      "phone_ts_ms,acc_x,acc_y,acc_z",
      "1000,0.500000,-1.000000,9.810000",
      "1020,0.250000,,9.800000",
    ]);
    expect(await files["wifi"]!.readAsLines(), <String>[
      "phone_ts_ms,wifi_name_list,wifi_sig_strength",
      '1001,"Cafe, 2nd floor",-70',
    ]);
    expect(
      files["wifi"]!.path,
      endsWith("${Platform.pathSeparator}wifi_raw.csv"),
    );
  });

  test("clears files of an earlier recording on open", () async {
    File old = File("${directory.path}/gyroscope_raw.csv");
    File unrelated = File("${directory.path}/notes.txt");
    await old.writeAsString("old");
    await unrelated.writeAsString("keep");

    CsvSink sink = CsvSink(directory);
    await sink.open();
    await sink.close();

    expect(old.existsSync(), isFalse);
    expect(unrelated.existsSync(), isTrue);
  });
}
