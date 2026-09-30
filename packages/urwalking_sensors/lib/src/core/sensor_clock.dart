/// A shared, monotonic time base for sensor samples.
///
/// All sensors in a recording should take their timestamps from the same
/// clock, otherwise their samples cannot be aligned afterwards. The clock is
/// anchored to the wall-clock time once, when it is created, and from then on
/// only advances with a monotonic [Stopwatch]. Changes to the system time
/// (NTP corrections, the user changing the time zone, ...) therefore do not
/// cause jumps or reordering in the recorded data.
class SensorClock {
  /// Creates a clock anchored to the current wall-clock time.
  SensorClock() : _origin = DateTime.now(), _stopwatch = Stopwatch()..start();

  /// The clock used by every sensor that is not given its own clock.
  static final SensorClock shared = SensorClock();

  final DateTime _origin;
  final Stopwatch _stopwatch;

  /// The current time on this clock.
  DateTime now() => _origin.add(_stopwatch.elapsed);
}
