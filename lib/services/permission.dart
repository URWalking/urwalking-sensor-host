import "dart:io";

import "package:geolocator/geolocator.dart";
import "package:permission_handler/permission_handler.dart";

class PermissionService {
  PermissionStatus? _activityStatus;
  PermissionStatus? _cameraStatus;
  PermissionStatus? _storageStatus;
  PermissionStatus? _bluetoothStatus;

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

  Future<PermissionStatus> requestCameraPermission() async {
    _cameraStatus = await Permission.camera.status;
    if (!_cameraStatus!.isGranted) {
      _cameraStatus = await Permission.camera.request();
    }
    return _cameraStatus!;
  }

  Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) {
      _storageStatus = PermissionStatus.granted;
      return true;
    }
    _storageStatus = await Permission.manageExternalStorage.status;
    if (!_storageStatus!.isGranted) {
      _storageStatus = await Permission.manageExternalStorage.request();
    }
    return _storageStatus!.isGranted;
  }

  Future<PermissionStatus> requestBluetoothPermission() async {
    if (!Platform.isAndroid) {
      _bluetoothStatus = PermissionStatus.granted;
      return _bluetoothStatus!;
    }
    final PermissionStatus scan = await Permission.bluetoothScan.request();
    await Permission.bluetoothConnect.request();
    _bluetoothStatus = scan;
    return _bluetoothStatus!;
  }

  bool isActivityPermissionGranted() => _activityStatus?.isGranted ?? false;
  bool isCameraPermissionGranted() => _cameraStatus?.isGranted ?? false;
  bool isStoragePermissionGranted() => _storageStatus?.isGranted ?? false;
  bool isBluetoothPermissionGranted() => _bluetoothStatus?.isGranted ?? false;

  String get storagePermissionStatus => _storageStatus?.name ?? "unknown";


  PermissionStatus? get activityStatus => _activityStatus;
  PermissionStatus? get cameraStatus => _cameraStatus;


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

  String get cameraPermissionStatus => _cameraStatus?.name ?? "unknown";

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
