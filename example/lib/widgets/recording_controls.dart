import "package:flutter/material.dart";
import "package:urwalking_sensors_network/urwalking_sensors_network.dart";

/// A set of controls for recording and sending sensor data
class RecordingControls extends StatelessWidget {
  const RecordingControls({
    super.key,
    required this.isRecording,
    required this.isSendingData,
    required this.streamLive,
    required this.transferImages,
    required this.streamingStatus,
    required this.sendStatusMessage,
    required this.onToggleRecording,
    required this.onSendLastData,
    required this.onStreamLiveChanged,
    required this.onTransferImagesChanged,
  });

  final bool isRecording;
  final bool isSendingData;
  final bool streamLive;
  final bool transferImages;
  final ConnectionStatus streamingStatus;
  final String? sendStatusMessage;
  final VoidCallback onToggleRecording;
  final VoidCallback onSendLastData;
  final ValueChanged<bool> onStreamLiveChanged;
  final ValueChanged<bool> onTransferImagesChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      SwitchListTile(
        title: const Text("Stream live to PC"),
        subtitle: isRecording && streamLive
            ? Text(streamingStatus.name)
            : const Text("Samples and clock sync, while recording"),
        value: streamLive,
        onChanged: isRecording ? null : onStreamLiveChanged,
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
      const SizedBox(height: 8),
      ElevatedButton(
        onPressed: (isRecording || isSendingData) ? null : onSendLastData,
        child: const Text("Send Last Data"),
      ),
    ],
  );
}
