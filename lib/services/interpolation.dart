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

extension on num {}

List<DateTime> uniformTimestamps(
  List<MeasuredPoint> measured,
  int targetSamplesPerSecond,
) {
  List<DateTime> result = [];
  DateTime t = measured.first.timestamp;
  DateTime end = measured.last.timestamp;
  Duration step = Duration(
    microseconds: (1e6 / targetSamplesPerSecond).round(),
  );
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
  assert(measured.length >= 2, "Need at least 2 points for PCHIP");

  final List<MeasuredPoint> sorted = List<MeasuredPoint>.from(measured)
    ..sort(
      (MeasuredPoint a, MeasuredPoint b) => a.timestamp.compareTo(b.timestamp),
    );

  final int pointCount = sorted.length;
  final List<Seconds> sampleTimes = <Seconds>[
    for (final MeasuredPoint point in sorted) point.timestamp.toSeconds(),
  ];
  final List<double> values = <double>[
    for (final MeasuredPoint point in sorted) point.value,
  ];

  // Step 1: Compute secant slopes between consecutive points.
  final List<double> secants = <double>[];
  for (int i = 0; i < pointCount - 1; i++) {
    final double h = sampleTimes[i + 1] - sampleTimes[i];
    secants.add((values[i + 1] - values[i]) / h);
  }

  // Step 2: Compute initial slopes at each point (monotone-preserving).
  final List<double> slopes = List<double>.filled(pointCount, 0);

  for (int i = 0; i < pointCount; i++) {
    if (i == 0) {
      // Boundary: use forward slope.
      slopes[i] = secants[0];
    } else if (i == pointCount - 1) {
      // Boundary: use backward slope.
      slopes[i] = secants[pointCount - 2];
    } else {
      // Interior: use average of adjacent secants, but only if both have same sign.
      final double s1 = secants[i - 1];
      final double s2 = secants[i];
      if (s1 * s2 <= 0) {
        // Sign change: slope is zero.
        slopes[i] = 0;
      } else {
        // Same sign: use harmonic mean to avoid overshoot.
        final double h1 = sampleTimes[i] - sampleTimes[i - 1];
        final double h2 = sampleTimes[i + 1] - sampleTimes[i];
        slopes[i] = (3 * (h1 + h2)) / (h1 / s1 + h2 / s2);
      }
    }
  }

  // Step 3: Modify slopes to ensure no overshoot between points.
  for (int i = 0; i < pointCount - 1; i++) {
    final double s = secants[i];
    if (s == 0) {
      slopes[i] = 0;
      slopes[i + 1] = 0;
    } else {
      final double alpha = slopes[i] / s;
      final double beta = slopes[i + 1] / s;
      final double tau = 3 / ((alpha + beta).abs() + 1e-14);
      if (alpha.abs() > tau) {
        slopes[i] = tau * s;
      }
      if (beta.abs() > tau) {
        slopes[i + 1] = tau * s;
      }
    }
  }

  final List<DateTime> uniform = uniformTimestamps(
    sorted,
    targetSamplesPerSecond,
  );

  int segment = 0;
  final List<DataPoint> result = <DataPoint>[];

  // Only output uniform grid timestamps for perfect consistency
  for (final DateTime queryTime in uniform) {
    final Seconds querySeconds = queryTime.toSeconds();
    while (segment < pointCount - 2 &&
        sampleTimes[segment + 1] < querySeconds) {
      segment++;
    }

    final Seconds t0 = sampleTimes[segment];
    final Seconds t1 = sampleTimes[segment + 1];
    final double y0 = values[segment];
    final double y1 = values[segment + 1];
    final double s0 = slopes[segment];
    final double s1 = slopes[segment + 1];
    final double h = t1 - t0;
    final double t = (querySeconds - t0) / h; // 0 to 1

    // Cubic Hermite basis functions.
    final double h00 = (1 + 2 * t) * (1 - t) * (1 - t);
    final double h10 = t * (1 - t) * (1 - t);
    final double h01 = t * t * (3 - 2 * t);
    final double h11 = t * t * (t - 1);

    final double value = h00 * y0 + h10 * h * s0 + h01 * y1 + h11 * h * s1;

    result.add(InterpolatedPoint(queryTime, value));
  }

  return result;
}
