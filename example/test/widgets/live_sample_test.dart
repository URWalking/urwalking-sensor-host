import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:urwalking_sensor_host/widgets/live_sample.dart";
import "package:urwalking_sensor_host/widgets/sensor_card.dart";
import "package:urwalking_sensors/urwalking_sensors.dart";

/// A sensor fed by hand, standing in for a platform sensor.
class FakeSensor extends StreamSensor {
  FakeSensor(this.id);

  @override
  final String id;

  final StreamController<SensorSample> _source =
      StreamController<SensorSample>.broadcast();

  void emit(Map<String, Object?> values, {DateTime? timestamp}) =>
      _source.add(
        SensorSample(
          sensorId: id,
          timestamp: timestamp ?? clock.now(),
          values: values,
        ),
      );

  void fail(Object error) => _source.addError(error);

  @override
  Stream<SensorSample> openSource() => _source.stream;

  @override
  Future<void> dispose() async {
    await _source.close();
    await super.dispose();
  }
}

void main() {
  testWidgets("SensorCard shows the latest sample of a sensor", (
    WidgetTester tester,
  ) async {
    FakeSensor sensor = FakeSensor("accelerometer");
    LiveSample live = LiveSample();
    await live.attach(sensor);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SensorCard(
            title: "Accelerometer",
            tick: live,
            buildReadings: () => <String>["X: ${live.number("acc_x")}"],
          ),
        ),
      ),
    );
    await tester.tap(find.text("Accelerometer"));
    await tester.pumpAndSettle();
    expect(find.text("X: -"), findsOneWidget);

    sensor.emit(<String, Object?>{"acc_x": 1.234});
    // The first frame delivers the sample through the sensor's streams,
    // the second one shows it.
    await tester.pump();
    await tester.pump();
    expect(find.text("X: 1.23"), findsOneWidget);

    live.dispose();
    // Awaiting the disposal hangs under testWidgets' fake async zone (it
    // completes in the plain tests below), so it is not awaited here.
    unawaited(sensor.dispose());
  });

  test("LiveSample reports sensor errors", () async {
    FakeSensor sensor = FakeSensor("gps");
    List<Object> errors = <Object>[];
    LiveSample live = LiveSample(onError: errors.add);
    await live.attach(sensor);

    sensor.fail(StateError("permission denied"));
    await pumpEventQueue();

    expect(errors, hasLength(1));
    live.dispose();
    await sensor.dispose();
  });

  test("LiveScan keeps only the items of the latest scan", () async {
    FakeSensor sensor = FakeSensor("wifi");
    LiveScan live = LiveScan();
    await live.attach(sensor);
    DateTime firstScan = DateTime(2026);
    DateTime secondScan = firstScan.add(const Duration(seconds: 30));

    sensor
      ..emit(<String, Object?>{"wifi_bssid": "a"}, timestamp: firstScan)
      ..emit(<String, Object?>{"wifi_bssid": "b"}, timestamp: firstScan);
    await pumpEventQueue();
    expect(live.items, hasLength(2));

    sensor.emit(<String, Object?>{"wifi_bssid": "c"}, timestamp: secondScan);
    await pumpEventQueue();
    expect(
      live.items.map((SensorSample s) => s.values["wifi_bssid"]),
      <String>["c"],
    );

    live.dispose();
    await sensor.dispose();
  });

  test("Detaching stops the sensor", () async {
    FakeSensor sensor = FakeSensor("gyroscope");
    LiveSample live = LiveSample();
    await live.attach(sensor);
    expect(live.isAttached, isTrue);

    await live.detach();
    sensor.emit(<String, Object?>{"gyro_x": 1});
    await pumpEventQueue();

    expect(live.isAttached, isFalse);
    expect(live.value, isNull);
    live.dispose();
    await sensor.dispose();
  });
}
