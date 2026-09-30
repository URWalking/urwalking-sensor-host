import "dart:io";

import "package:flutter/foundation.dart";
import "package:flutter/services.dart";

/// The channel implemented by the native side of this plugin.
@internal
const MethodChannel cameraChannel = MethodChannel(
  "urwalking_sensors_camera/camera",
);

/// Which way a camera faces.
enum CameraFacing {
  /// Towards the user.
  front,

  /// Away from the user.
  back,

  /// An external (e.g. USB) camera.
  external,

  /// Not reported by the platform.
  unknown;

  /// Maps Android's `LENS_FACING` constants.
  static CameraFacing fromPlatform(int? value) => switch (value) {
    0 => front,
    1 => back,
    2 => external,
    _ => unknown,
  };
}

/// A camera reported by the platform.
@immutable
class CameraInfo {
  /// Creates a camera description.
  const CameraInfo({
    required this.id,
    required this.name,
    required this.facing,
    this.isLogical = false,
    this.parentLogicalId,
  });

  /// Parses one entry of the native `listCameras` result.
  factory CameraInfo.fromMap(Map<Object?, Object?> map) => CameraInfo(
    id: map["id"]! as String,
    name: map["name"]! as String,
    facing: CameraFacing.fromPlatform(map["facing"] as int?),
    isLogical: map["isLogical"] as bool? ?? false,
    parentLogicalId: map["parentLogicalId"] as String?,
  );

  /// The platform's camera id.
  final String id;

  /// A human-readable name, e.g. `Camera 0 (Back)`.
  final String name;

  /// Which way the camera faces.
  final CameraFacing facing;

  /// Whether this is a logical multi-camera made of several lenses.
  final bool isLogical;

  /// For a physical lens: the logical camera it belongs to.
  final String? parentLogicalId;
}

/// Captures JPEG camera frames (640×480) to files while recording.
///
/// Frames are written to `<recording directory>/images/frame_<ms>.jpg`.
/// When capture stops, `images_raw.csv` (`phone_ts_ms,img_file`) is written
/// next to the sensor CSVs, so the PC receiver combines frames with the
/// other sensors.
///
/// Frame timestamps are taken natively with the wall clock, while sensors
/// use `SensorClock`. On Android the camera can be shared with ARCore; see
/// ArPoseSensor. On iOS, frames come from the ARKit session, so capture
/// only works while ArPoseSensor's session runs.
class FrameCapture {
  /// Creates a frame capture. Errors are reported to [onError].
  FrameCapture({this.onError});

  /// Called with a message for the user when something fails.
  final void Function(String message)? onError;

  List<CameraInfo> _cameras = <CameraInfo>[];
  Set<String> _selectedCameraIds = <String>{};
  Directory? _recordingDirectory;

  /// The cameras found by [loadCameras].
  List<CameraInfo> get cameras => List<CameraInfo>.unmodifiable(_cameras);

  /// The cameras that [start] captures from. Currently only the first one
  /// is used.
  Set<String> get selectedCameraIds =>
      Set<String>.unmodifiable(_selectedCameraIds);

  /// Whether frames are being captured.
  bool get isCapturing => _recordingDirectory != null;

  /// Lists the cameras and selects the back camera(s) to capture from.
  ///
  /// Requires the camera permission.
  Future<void> loadCameras() async {
    try {
      Map<Object?, Object?>? raw = await cameraChannel
          .invokeMapMethod<Object?, Object?>("listCameras");
      _cameras = <CameraInfo>[
        for (Object? camera in raw?["cameras"] as List<Object?>? ?? <Object?>[])
          CameraInfo.fromMap(camera! as Map<Object?, Object?>),
      ];
      List<List<String>> concurrentSets = <List<String>>[
        for (Object? set
            in raw?["concurrentSets"] as List<Object?>? ?? <Object?>[])
          (set! as List<Object?>).cast<String>(),
      ];
      if (concurrentSets.isNotEmpty) {
        _selectedCameraIds = concurrentSets
            .reduce(
              (List<String> a, List<String> b) => a.length >= b.length ? a : b,
            )
            .toSet();
      } else {
        _selectBackCamera();
      }
      // Keep only back cameras.
      _selectedCameraIds.retainWhere(
        (String id) => _cameras.any(
          (CameraInfo camera) =>
              camera.id == id && camera.facing == CameraFacing.back,
        ),
      );
    } on PlatformException catch (e) {
      onError?.call("Failed to list cameras: ${e.message}");
      _selectBackCamera();
    } on MissingPluginException {
      _cameras = <CameraInfo>[];
      _selectedCameraIds = <String>{};
    }
  }

  /// Captures from [cameraId] only, e.g. the camera ARCore shares.
  void useCamera(String cameraId) => _selectedCameraIds = <String>{cameraId};

  void _selectBackCamera() {
    CameraInfo? back = _cameras
        .where((CameraInfo camera) => camera.facing == CameraFacing.back)
        .firstOrNull;
    _selectedCameraIds = <String>{?back?.id};
  }

  /// Opens the selected cameras. Not needed for a camera shared with
  /// ARCore, which is already open.
  Future<void> openCameras() async {
    for (String id in _selectedCameraIds) {
      try {
        await cameraChannel.invokeMethod<int>("openCamera", <String, Object?>{
          "cameraId": id,
        });
        await Future<void>.delayed(const Duration(milliseconds: 500));
      } on PlatformException catch (e) {
        onError?.call("Failed to open camera $id: ${e.message}");
      }
    }
  }

  /// Starts writing frames into `images/` inside [recordingDirectory].
  /// Frames of an earlier recording in that folder are deleted first.
  Future<void> start(Directory recordingDirectory) async {
    if (_selectedCameraIds.isEmpty) {
      return;
    }
    Directory imagesDir = _imagesDirectory(recordingDirectory);
    // Wipe the images of a previous recording, so each upload only
    // contains its own frames.
    if (imagesDir.existsSync()) {
      await imagesDir.delete(recursive: true);
    }
    await imagesDir.create(recursive: true);
    try {
      await cameraChannel.invokeMethod<void>(
        "startFastCapture",
        <String, Object?>{
          "cameraId": _selectedCameraIds.first,
          "outputDir": imagesDir.path,
        },
      );
      _recordingDirectory = recordingDirectory;
    } on PlatformException catch (e) {
      onError?.call("Starting frame capture failed: ${e.message}");
    }
  }

  /// Stops writing frames and writes `images_raw.csv`.
  Future<void> stop() async {
    Directory? recordingDirectory = _recordingDirectory;
    if (recordingDirectory == null) {
      return;
    }
    _recordingDirectory = null;
    try {
      await cameraChannel.invokeMethod<void>(
        "stopFastCapture",
        <String, Object?>{"cameraId": _selectedCameraIds.first},
      );
    } on PlatformException catch (e) {
      onError?.call("Stopping frame capture failed: ${e.message}");
    }
    try {
      await writeFramesCsv(recordingDirectory);
    } on FileSystemException catch (e) {
      onError?.call("Writing images_raw.csv failed: ${e.message}");
    }
  }

  /// Stops capturing and closes all cameras.
  Future<void> dispose() async {
    await stop();
    try {
      await cameraChannel.invokeMethod<void>("closeCamera");
    } on MissingPluginException {
      // Nothing to close on platforms without the native side.
    }
  }

  static Directory _imagesDirectory(Directory recordingDirectory) =>
      Directory("${recordingDirectory.path}${Platform.pathSeparator}images");
}

/// Converts the frame log written natively (`images/image_timestamps.csv`)
/// into `images_raw.csv` in [recordingDirectory], in the format of the
/// other sensor CSVs. Does nothing if no frames were captured.
Future<void> writeFramesCsv(Directory recordingDirectory) async {
  String separator = Platform.pathSeparator;
  File frameLog = File(
    "${recordingDirectory.path}${separator}images$separator"
    "image_timestamps.csv",
  );
  if (!frameLog.existsSync()) {
    return;
  }
  StringBuffer csv = StringBuffer()..writeln("phone_ts_ms,img_file");
  for (String line in (await frameLog.readAsLines()).skip(1)) {
    List<String> parts = line.split(",");
    if (parts.length >= 2 && int.tryParse(parts[0].trim()) != null) {
      csv.writeln("${parts[0].trim()},${parts[1].trim()}");
    }
  }
  await File(
    "${recordingDirectory.path}${separator}images_raw.csv",
  ).writeAsString(csv.toString(), flush: true);
}
