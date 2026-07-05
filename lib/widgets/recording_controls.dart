import "package:flutter/material.dart";
import "package:urwalking_sensor_host/services/streaming_service.dart";

/// A set of controls for recording and sending sensor data
class RecordingControls extends StatelessWidget {
  const RecordingControls({
    super.key,
    required this.isRecording,
    required this.isSendingData,
    required this.streamTimestamps,
    required this.transferImages,
    required this.streamingStatus,
    required this.sendStatusMessage,
    required this.onResetSessionSteps,
    required this.onToggleRecording,
    required this.onStreamTimestampsChanged,
    required this.onTransferImagesChanged,
  });

  final bool isRecording;
  final bool isSendingData;
  final bool streamTimestamps;
  final bool transferImages;
  final StreamingStatus streamingStatus;
  final String? sendStatusMessage;
  final VoidCallback onResetSessionSteps;
  final VoidCallback onToggleRecording;
  final ValueChanged<bool> onStreamTimestampsChanged;
  final ValueChanged<bool> onTransferImagesChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      ElevatedButton(
        onPressed: onResetSessionSteps,
        child: const Text("Reset Session Steps"),
      ),
      const SizedBox(height: 8),
      SwitchListTile(
        title: const Text("Timestamps streamen"),
        subtitle: isRecording && streamTimestamps
            ? Text(streamingStatus.name)
            : null,
        value: streamTimestamps,
        onChanged: isRecording ? null : onStreamTimestampsChanged,
      ),
      SwitchListTile(
        title: const Text("Transfer images"),
        subtitle: const Text("Turn off for a quicker CSV-only send"),
        value: transferImages,
        onChanged: (isRecording || isSendingData)
            ? null
            : onTransferImagesChanged,
      ),
      if (isSendingData) ...<Widget>[
        const SizedBox(height: 8),
        Card(
          color: Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "${sendStatusMessage ?? "Sending…"}\n"
                    "Keep the phone connected and awake until this finishes.",
                    style: TextStyle(color: Colors.amber.shade900),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      const SizedBox(height: 8),
      ElevatedButton(
        onPressed: isSendingData ? null : onToggleRecording,
        style: ElevatedButton.styleFrom(
          backgroundColor: isRecording ? Colors.green : Colors.grey,
        ),
        child: Text(
          isSendingData
              ? "Sending…"
              : (isRecording ? "Stop Recording & Send" : "Start Recording"),
        ),
      ),
    ],
  );
}
