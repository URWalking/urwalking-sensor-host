import "dart:async";

import "package:test/test.dart";
import "package:urwalking_sensors/urwalking_sensors.dart";

/// A sensor fed by hand, so tests control exactly when samples arrive.
class FakeSensor extends StreamSensor {
  FakeSensor(this.id);

  @override
  final String id;

  StreamController<SensorSample>? _source;
  int openCount = 0;

  bool get isOpen => _source != null;

  void emit(Map<String, Object?> values) => _source!.add(
    SensorSample(sensorId: id, timestamp: clock.now(), values: values),
  );

  void fail(Object error) => _source!.addError(error);

  @override
  Stream<SensorSample> openSource() {
    openCount++;
    late StreamController<SensorSample> source;
    source = StreamController<SensorSample>(
      onCancel: () {
        _source = null;
        return source.close();
      },
    );
    _source = source;
    return source.stream;
  }
}

void main() {
  test("StreamSensor only opens its source while someone listens", () async {
    FakeSensor sensor = FakeSensor("fake");
    expect(sensor.isOpen, isFalse);

    StreamSubscription<SensorSample> subscription = sensor.samples.listen(
      (_) {},
    );
    expect(sensor.isOpen, isTrue);

    await subscription.cancel();
    expect(sensor.isOpen, isFalse);

    await sensor.samples.listen((_) {}).cancel();
    expect(sensor.openCount, 2);
    await sensor.dispose();
  });

  test("Recorder passes samples of every sensor to every sink", () async {
    FakeSensor a = FakeSensor("a");
    FakeSensor b = FakeSensor("b");
    MemorySink first = MemorySink();
    MemorySink second = MemorySink();
    Recorder recorder = Recorder(
      sensors: <Sensor>[a, b],
      sinks: <SampleSink>[first, second],
    );

    await recorder.start();
    a.emit(<String, Object?>{"x": 1});
    b.emit(<String, Object?>{"y": 2});
    a.emit(<String, Object?>{"x": 3});
    await pumpEventQueue();
    await recorder.stop();

    for (MemorySink sink in <MemorySink>[first, second]) {
      expect(sink.samples.map((SensorSample s) => s.sensorId), <String>[
        "a",
        "b",
        "a",
      ]);
      expect(sink.samplesOf("a").last.values["x"], 3);
    }
    expect(a.isOpen, isFalse);
    await recorder.dispose();
  });

  test("A failing sensor is reported and does not stop the others", () async {
    FakeSensor good = FakeSensor("good");
    FakeSensor bad = FakeSensor("bad");
    MemorySink sink = MemorySink();
    Recorder recorder = Recorder(
      sensors: <Sensor>[good, bad],
      sinks: <SampleSink>[sink],
    );
    List<SensorError> errors = <SensorError>[];
    StreamSubscription<SensorError> errorSubscription = recorder.errors.listen(
      errors.add,
    );

    await recorder.start();
    bad.fail(StateError("broken"));
    good.emit(<String, Object?>{"x": 1});
    await pumpEventQueue();
    await recorder.stop();

    expect(errors.single.sensorId, "bad");
    expect(sink.samplesOf("good"), hasLength(1));
    await errorSubscription.cancel();
    await recorder.dispose();
  });

  test("Recorder cannot be started twice", () async {
    Recorder recorder = Recorder(sensors: <Sensor>[], sinks: <SampleSink>[]);
    await recorder.start();
    expect(recorder.start, throwsStateError);
    await recorder.dispose();
  });

  test("SensorClock never goes backwards", () {
    SensorClock clock = SensorClock();
    DateTime previous = clock.now();
    for (int i = 0; i < 1000; i++) {
      DateTime next = clock.now();
      expect(next.isBefore(previous), isFalse);
      previous = next;
    }
  });
}
