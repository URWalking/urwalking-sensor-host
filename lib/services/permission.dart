import "dart:io";

import "package:permission_handler/permission_handler.dart";

class PermissionService {
  PermissionStatus? _currentStatus;

  Future<PermissionStatus> requestActivityPermission() async {
    if (!Platform.isAndroid) {
      // can't test on IOS so just did this for now
      _currentStatus = PermissionStatus.granted;
      return _currentStatus!;
    }

    _currentStatus = await Permission.activityRecognition.status;
    if (!_currentStatus!.isGranted) {
      _currentStatus = await Permission.activityRecognition.request();
    }
    return _currentStatus!;
  }

  bool isActivityPermissionGranted() => _currentStatus?.isGranted ?? false;

  PermissionStatus? get currentStatus => _currentStatus;
}
