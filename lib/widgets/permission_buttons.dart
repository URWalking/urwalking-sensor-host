import "package:flutter/material.dart";

/// One "Request X Permission" button per permission not yet granted; each
/// disappears once its permission is granted.
class PermissionButtons extends StatelessWidget {
  const PermissionButtons({
    super.key,
    required this.hasStoragePermission,
    required this.hasActivityPermission,
    required this.hasLocationPermission,
    required this.hasCameraPermission,
    required this.hasBluetoothPermission,
    required this.onRequestStorage,
    required this.onRequestActivity,
    required this.onRequestLocation,
    required this.onRequestCamera,
    required this.onRequestBluetooth,
  });

  final bool hasStoragePermission;
  final bool hasActivityPermission;
  final bool hasLocationPermission;
  final bool hasCameraPermission;
  final bool hasBluetoothPermission;
  final VoidCallback onRequestStorage;
  final VoidCallback onRequestActivity;
  final VoidCallback onRequestLocation;
  final VoidCallback onRequestCamera;
  final VoidCallback onRequestBluetooth;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      if (!hasStoragePermission) ...<Widget>[
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: onRequestStorage,
          child: const Text("Request Storage Permission"),
        ),
      ],
      if (!hasActivityPermission) ...<Widget>[
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: onRequestActivity,
          child: const Text("Request Activity Permission"),
        ),
      ],
      if (!hasLocationPermission) ...<Widget>[
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: onRequestLocation,
          child: const Text("Request Location Permission"),
        ),
      ],
      if (!hasCameraPermission) ...<Widget>[
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: onRequestCamera,
          child: const Text("Request Camera Permission"),
        ),
      ],
      if (!hasBluetoothPermission) ...<Widget>[
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: onRequestBluetooth,
          child: const Text("Request Bluetooth Permission"),
        ),
      ],
    ],
  );
}
