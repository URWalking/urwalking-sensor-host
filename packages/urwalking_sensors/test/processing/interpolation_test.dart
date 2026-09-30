import "package:test/test.dart";
import "package:urwalking_sensors/urwalking_sensors.dart";

MeasuredPoint _point(int ms, double value) =>
    MeasuredPoint(DateTime.fromMillisecondsSinceEpoch(ms), value);

void main() {
  test("produces a uniform grid from the first to the last sample", () {
    List<DataPoint> result = interpolate(<MeasuredPoint>[
      _point(0, 0),
      _point(35, 1),
      _point(100, 2),
    ], 100);

    expect(result, hasLength(11));
    for (int i = 0; i < result.length; i++) {
      expect(result[i].timestamp.millisecondsSinceEpoch, i * 10);
      expect(result[i], isA<InterpolatedPoint>());
    }
  });

  test("reproduces the measured values at the measured times", () {
    List<DataPoint> result = interpolate(<MeasuredPoint>[
      _point(0, 1),
      _point(50, 4),
      _point(100, 2),
    ], 100);

    expect(result.first.value, closeTo(1, 1e-9));
    expect(result[5].value, closeTo(4, 1e-9));
    expect(result.last.value, closeTo(2, 1e-9));
  });

  test("does not overshoot the measured values", () {
    List<DataPoint> result = interpolate(<MeasuredPoint>[
      _point(0, 0),
      _point(10, 0),
      _point(20, 10),
      _point(30, 10),
    ], 1000);

    for (DataPoint point in result) {
      expect(point.value, inInclusiveRange(-1e-9, 10 + 1e-9));
    }
  });

  test("accepts unsorted input", () {
    List<DataPoint> sorted = interpolate(<MeasuredPoint>[
      _point(0, 0),
      _point(50, 5),
      _point(100, 0),
    ], 50);
    List<DataPoint> unsorted = interpolate(<MeasuredPoint>[
      _point(100, 0),
      _point(0, 0),
      _point(50, 5),
    ], 50);

    expect(
      unsorted.map((DataPoint p) => p.value),
      sorted.map((DataPoint p) => p.value),
    );
  });
}
