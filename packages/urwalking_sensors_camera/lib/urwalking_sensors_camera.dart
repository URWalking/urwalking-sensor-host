/// Camera frame capture and AR pose for `urwalking_sensors`.
///
/// On Android, [ArPoseSensor] and [FrameCapture] share one camera through
/// ARCore's SharedCamera API, so frames and pose can be recorded together.
/// On iOS, only [ArPoseSensor] (ARKit) is implemented so far.
library;

import "package:urwalking_sensors_camera/src/ar_pose_sensor.dart";
import "package:urwalking_sensors_camera/src/frame_capture.dart";

export "src/ar_pose_sensor.dart";
export "src/frame_capture.dart" hide cameraChannel;
