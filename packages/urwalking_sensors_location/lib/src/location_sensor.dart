import "dart:async";

import "package:geolocator/geolocator.dart";
import "package:urwalking_sensors/urwalking_sensors.dart";

/// The device position from GPS and other location providers.
///
/// Fields:
/// - `gps_lat`, `gps_lon`: position in degrees (WGS84)
/// - `gps_alt`: altitude in m
/// - `gps_accuracy`: horizontal accuracy in m
/// - `gps_speed`: speed in m/s
/// - `gps_heading`: direction of travel in degrees
/// - `gps_fix_ts_ms`: when the platform computed the fix, in ms since the
///   Unix epoch, on the wall clock (the sample timestamp is when the fix
///   arrived, on the shared SensorClock)
///
/// Requires location permission. The app has to request it (e.g. with
/// [Geolocator.requestPermission]) before listening. If the user turns off
/// the location service while listening, samples pause and resume
/// automatically once it is turned back on.
class LocationSensor extends StreamSensor {
  /// Creates a location sensor. [settings] defaults to the highest accuracy
  /// and no distance filter, i.e. every update is delivered.
  LocationSensor({super.clock, LocationSettings? settings})
    : settings = settings ?? const LocationSettings();

  /// The accuracy and filter settings passed to the platform.
  final LocationSettings settings;

  @override
  String get id => "location";

  @override
  Future<bool> isAvailable() async {
    LocationPermission permission = await Geolocator.checkPermission();
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Whether the device's location service is currently turned on.
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  /// Emits whenever the user turns the location service on or off.
  Stream<bool> get serviceEnabledChanges => Geolocator.getServiceStatusStream()
      .map((ServiceStatus status) => status == ServiceStatus.enabled);

  @override
  Stream<SensorSample> openSource() {
    StreamSubscription<Position>? positions;
    StreamSubscription<ServiceStatus>? serviceStatus;
    late StreamController<SensorSample> controller;

    Future<void> stopPositions() async {
      await positions?.cancel();
      positions = null;
    }

    void startPositions() {
      positions = Geolocator.getPositionStream(locationSettings: settings)
          .listen(
            (Position position) => controller.add(_sample(position)),
            onError: controller.addError,
          );
    }

    controller = StreamController<SensorSample>(
      onListen: () {
        serviceStatus = Geolocator.getServiceStatusStream().listen(
          (ServiceStatus status) async {
            if (status == ServiceStatus.enabled && positions == null) {
              startPositions();
            } else if (status == ServiceStatus.disabled) {
              await stopPositions();
            }
          },
          // Not every platform reports service changes. Positions still
          // work there, they just do not resume automatically.
          onError: (Object error) => serviceStatus = null,
        );
        startPositions();
      },
      onCancel: () async {
        await stopPositions();
        await serviceStatus?.cancel();
        serviceStatus = null;
        await controller.close();
      },
    );
    return controller.stream;
  }

  SensorSample _sample(Position position) => SensorSample(
    sensorId: id,
    timestamp: clock.now(),
    values: <String, Object?>{
      "gps_lat": position.latitude,
      "gps_lon": position.longitude,
      "gps_alt": position.altitude,
      "gps_accuracy": position.accuracy,
      "gps_speed": position.speed,
      "gps_heading": position.heading,
      "gps_fix_ts_ms": position.timestamp.millisecondsSinceEpoch,
    },
  );
}
