import "dart:io";

import "package:geolocator/geolocator.dart";
import "package:permission_handler/permission_handler.dart";

class PermissionService {
  PermissionStatus? _activityStatus;

  // Geolocator has its own permission type, separate from permission_handler.
  LocationPermission _locationPermission = LocationPermission.denied;
  bool _locationServiceEnabled = false;

  // Activity (pedometer)

  Future<PermissionStatus> requestActivityPermission() async {
    if (!Platform.isAndroid) {
      _activityStatus = PermissionStatus.granted;
      return _activityStatus!;
    }

    _activityStatus = await Permission.activityRecognition.status;
    if (!_activityStatus!.isGranted) {
      _activityStatus = await Permission.activityRecognition.request();
    }
    return _activityStatus!;
  }

  bool isActivityPermissionGranted() => _activityStatus?.isGranted ?? false;

  PermissionStatus? get activityStatus => _activityStatus;

  // Location (via geolocator)

  /// Returns true if permission was ultimately granted and the location service
  /// is enabled. Mirrors the canonical geolocator permission flow from the docs.
  Future<bool> requestLocationPermission() async {
    // 1. Check whether the device location service itself is on.
    _locationServiceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!_locationServiceEnabled) {
      // Don't request permission when the service is off — it won't help.
      return false;
    }

    // 2. Check current permission state.
    _locationPermission = await Geolocator.checkPermission();

    // 3. If denied (but not permanently), ask once.
    if (_locationPermission == LocationPermission.denied) {
      _locationPermission = await Geolocator.requestPermission();
      if (_locationPermission == LocationPermission.denied) {
        return false;
      }
    }

    // 4. If permanently denied, we can't request again — caller should show
    //    a message directing the user to app settings.
    // TODO(SpacEagle17): link to app settings from the UI when this happens.
    if (_locationPermission == LocationPermission.deniedForever) {
      return false;
    }

    // whileInUse or always → granted
    return true;
  }

  bool isLocationPermissionGranted() =>
      _locationPermission == LocationPermission.whileInUse ||
      _locationPermission == LocationPermission.always;

  bool get locationServiceEnabled => _locationServiceEnabled;

  /// Human-readable status string for the UI (mirrors what the dashboard shows
  /// for activity permission).
  String get locationPermissionStatus {
    if (!_locationServiceEnabled) {
      return "service disabled";
    }
    return switch (_locationPermission) {
      LocationPermission.denied => "denied",
      LocationPermission.deniedForever => "denied forever",
      LocationPermission.whileInUse => "whileInUse",
      LocationPermission.always => "always",
      LocationPermission.unableToDetermine => "unable to determine",
    };
  }
}
