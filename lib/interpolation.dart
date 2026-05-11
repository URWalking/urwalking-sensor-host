sealed class DataPoint {
  final DateTime timestamp; 
  final double value;
  const DataPoint(this.timestamp, this.value);
}

final class MeasuredPoint extends DataPoint {
  const MeasuredPoint(super.timestamp, super.value);
}

final class InterpolatedPoint extends DataPoint {
  const InterpolatedPoint(super.timestamp, super.value);
}

extension type Seconds(double value) implements double {}

extension on DateTime {
  Seconds toSeconds() => Seconds(microsecondsSinceEpoch / 1e6);
}

extension on num {
  double cube() => (this * this * this).toDouble();
}

List<DateTime> uniformTimestamps(
  List<MeasuredPoint> measured,
  int targetSamplesPerSecond,
) {
  List<DateTime> result = [];
  DateTime t = measured.first.timestamp;
  DateTime end = measured.last.timestamp;
  Duration step = Duration(microseconds: (1e6 / targetSamplesPerSecond).round());
  while (!t.isAfter(end)) {
    result.add(t);
    t = t.add(step);
  }
  return result;
}

List<DataPoint> interpolate(
  List<MeasuredPoint> measured,
  int targetSamplesPerSecond,
) {
  assert(measured.length >= 3, "Need at least 3 points for cubic spline");

  int pointCount = measured.length;

  List<Seconds> sampleTimes = [
    for (MeasuredPoint point in measured) point.timestamp.toSeconds()
  ];

  List<Seconds> intervalWidths = [
    for (int i = 0; i < pointCount - 1; i++) 
      Seconds(sampleTimes[i + 1] - sampleTimes[i])
  ];

  // Tridiagonal right-hand side: encodes slope change at each interior knot
  List<double> slopeDeltas = List<double>.filled(pointCount, 0);
  for (int i = 1; i < pointCount - 1; i++) {
    slopeDeltas[i] =
        (3 / intervalWidths[i]) * (measured[i + 1].value - measured[i].value)
      - (3 / intervalWidths[i - 1]) * (measured[i].value - measured[i - 1].value);
  }

  // Thomas algorithm — forward sweep
  List<double> pivots          = List<double>.filled(pointCount, 1);
  List<double> upperDiagonal   = List<double>.filled(pointCount, 0);
  List<double> forwardResidual = List<double>.filled(pointCount, 0);
  for (int i = 1; i < pointCount - 1; i++) {
    pivots[i]          = 2 * (sampleTimes[i + 1] - sampleTimes[i - 1])
                       - intervalWidths[i - 1] * upperDiagonal[i - 1];
    upperDiagonal[i]   = intervalWidths[i] / pivots[i];
    forwardResidual[i] = (slopeDeltas[i] - intervalWidths[i - 1] * forwardResidual[i - 1])
                       / pivots[i];
  }

  // Thomas algorithm — back substitution
  List<double> secondDerivatives = List<double>.filled(pointCount, 0);
  for (int j = pointCount - 2; j >= 1; j--) {
    secondDerivatives[j] = forwardResidual[j] - upperDiagonal[j] * secondDerivatives[j + 1];
  }

  List<DateTime> queryTimestamps = uniformTimestamps(measured, targetSamplesPerSecond);
  Set<DateTime> measuredTimestamps = {
    for (MeasuredPoint point in measured) point.timestamp
  };

  int segment = 0;
  List<DataPoint> result = <DataPoint>[];

  for (DateTime queryTime in queryTimestamps) {
    Seconds querySeconds = queryTime.toSeconds();

    while (segment < pointCount - 2 && sampleTimes[segment + 1] <= querySeconds) segment++;

    Seconds segmentStart    = sampleTimes[segment];
    Seconds segmentEnd      = sampleTimes[segment + 1];
    double segmentWidth     = intervalWidths[segment];
    Seconds offsetFromStart = Seconds(querySeconds - segmentStart);
    double derivativeLeft   = secondDerivatives[segment];
    double derivativeRight  = secondDerivatives[segment + 1];

    double value =
        (derivativeLeft  / (6 * segmentWidth)) * (segmentEnd - querySeconds).cube()
      + (derivativeRight / (6 * segmentWidth)) * offsetFromStart.cube()
      + (measured[segment].value     / segmentWidth - derivativeLeft  * segmentWidth / 6) * (segmentEnd - querySeconds)
      + (measured[segment + 1].value / segmentWidth - derivativeRight * segmentWidth / 6) * offsetFromStart;

    result.add(
      measuredTimestamps.contains(queryTime)
          ? MeasuredPoint(queryTime, value)
          : InterpolatedPoint(queryTime, value),
    );
  }

  return result;
}

void main() {
  List<MeasuredPoint> measured = [
    MeasuredPoint(DateTime(2024, 1, 1, 0, 0, 0, 0),    10.0),
    MeasuredPoint(DateTime(2024, 1, 1, 0, 0, 1, 0),    21.5),
    MeasuredPoint(DateTime(2024, 1, 1, 0, 0, 1, 900),  22.1),
    MeasuredPoint(DateTime(2024, 1, 1, 0, 0, 3, 50),   21.8),
    MeasuredPoint(DateTime(2024, 1, 1, 0, 0, 4, 0),    20.5),
  ];

  List<DataPoint> resampled = interpolate(measured, 4);

  for (DataPoint point in resampled) {
    String kind = switch (point) {
      MeasuredPoint()     => "measured    ",
      InterpolatedPoint() => "interpolated",
    };
    print("$kind  ${point.timestamp.toSeconds()}s  →  ${point.value.toStringAsFixed(4)}");
  }
}