import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';


class MultiCamScreen extends StatefulWidget {
  const MultiCamScreen({super.key});

  @override
  State<MultiCamScreen> createState() => _MultiCamScreenState();
}

class CameraDevice {
  final String id;
  final String name;
  final int facing;

  CameraDevice({required this.id, required this.name, required this.facing});

  factory CameraDevice.fromMap(Map<dynamic, dynamic> map) {
    return CameraDevice(
      id: map['id'] as String,
      name: map['name'] as String,
      facing: map['facing'] as int,
    );
  }
}

class _MultiCamScreenState extends State<MultiCamScreen> {
  static const platform = MethodChannel('com.example.app/camera');

  List<CameraDevice> availableCameras = [];
  Map<String, int?> textureIds = {}; // { cameraId: textureId }
  Set<String> selectedCameras = {};
  Set<String> activeCameras = {}; // Currently streaming cameras

  bool _isLoading = false;
  bool _isStreaming = false;

  @override
  void initState() {
    super.initState();
    _loadAvailableCameras();
  }

  Future<void> _loadAvailableCameras() async {
    setState(() => _isLoading = true);
    try {
      var status = await Permission.camera.request();
      if (!status.isGranted) {
        debugPrint("Camera permission denied by user.");
        return;
      }

      final List<dynamic> cameras = await platform.invokeMethod('listCameras');
      debugPrint("🎥 Cameras available: ${cameras.length}");
      for (var cam in cameras) {
        debugPrint("  - ${cam['name']} (ID: ${cam['id']}, Facing: ${cam['facing']})");
      }
      
      if (mounted) {
        setState(() {
          availableCameras = cameras
              .map((cam) => CameraDevice.fromMap(cam as Map<dynamic, dynamic>))
              .toList();
        });
      }
    } on PlatformException catch (e) {
      debugPrint("Native Platform Error: ${e.message}");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: ${e.message}")),
        );
      }
    } catch (e) {
      debugPrint("General App Error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading cameras: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openSelectedCameras() async {
    if (selectedCameras.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select at least one camera")),
      );
      return;
    }

    setState(() => _isStreaming = true);

    try {
      for (String cameraId in selectedCameras) {
        if (!activeCameras.contains(cameraId)) {
          try {
            final int textureId =
                await platform.invokeMethod('openCamera', {'cameraId': cameraId});
            setState(() {
              textureIds[cameraId] = textureId;
              activeCameras.add(cameraId);
            });
            // Add delay between camera initializations
            await Future.delayed(const Duration(milliseconds: 500));
          } catch (e) {
            debugPrint("Error opening camera $cameraId: $e");
          }
        }
      }
    } catch (e) {
      debugPrint("General Error: $e");
    } finally {
      setState(() => _isStreaming = false);
    }
  }

  //Capture picture with singular lense
  Future<void> _triggerCapture(String cameraId) async {
    try {
      final String? filePath = await platform.invokeMethod("takePicture", {
        "cameraId": cameraId,
      });

      if (!mounted) return;

      if (filePath != null) {
        debugPrint("Photo saved at: $filePath");
        //path: /data/data/com.example.testing/files

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Captured: $filePath")),
        );
      }
    } on PlatformException catch (e) {
      debugPrint("Failed to capture: ${e.message}");
    }
  }

  //Capture all active lenses
  Future<void> _captureAll() async {
    if (activeCameras.isEmpty) return;

    //loader while processing multiple saves
    setState(() => _isLoading = true); 

    try {
      // Fire all capture methods simultaneously
      final List<Future<String?>> captureFutures = activeCameras.map((id) {
        return platform.invokeMethod<String>("takePicture", {"cameraId": id});
      }).toList();

      final List<String?> results = await Future.wait(captureFutures);
      
      int successCount = results.where((path) => path != null).length;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Captured $successCount photos successfully!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint("Error during multi-capture: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _closeAllCameras() async {
    try {
      await platform.invokeMethod('closeCamera');
      setState(() {
        activeCameras.clear();
        textureIds.clear();
      });
    } catch (e) {
      debugPrint("Error closing cameras: $e");
    }
  }

  void _toggleCameraSelection(String cameraId) {
    setState(() {
      if (selectedCameras.contains(cameraId)) {
        selectedCameras.remove(cameraId);
      } else {
        selectedCameras.add(cameraId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Multi-Camera Selector"),
        elevation: 4,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Camera Selection Panel
                Container(
                  color: Colors.grey[900],
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Available Cameras",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      availableCameras.isEmpty
                          ? const Text(
                              "No cameras found",
                              style: TextStyle(color: Colors.grey),
                            )
                          : Wrap(
                              spacing: 8,
                              children: availableCameras.map((cam) {
                                bool isSelected = selectedCameras.contains(cam.id);
                                bool isActive = activeCameras.contains(cam.id);
                                return FilterChip(
                                  label: Text(cam.name),
                                  selected: isSelected,
                                  onSelected: (_) =>
                                      _toggleCameraSelection(cam.id),
                                  backgroundColor: Colors.grey[800],
                                  selectedColor: Colors.blue,
                                  labelStyle: TextStyle(
                                    color: isSelected ? Colors.white : Colors.grey[300],
                                    fontWeight:
                                        isActive ? FontWeight.bold : FontWeight.normal,
                                  ),
                                );
                              }).toList(),
                            ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Camera Previews Grid
                Expanded(
                  child: activeCameras.isEmpty
                      ? Center(
                          child: Text(
                            _isStreaming
                                ? "Starting cameras..."
                                : "Select cameras and tap 'Start Streaming'",
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.grey),
                          ),
                        )
                      : GridView.count(
                          crossAxisCount:
                              activeCameras.length == 1 ? 1 : 2,
                          children: activeCameras.map((cameraId) {
                            return _buildCameraPreview(cameraId);
                          }).toList(),
                        ),
                ),
                // Control Buttons
                Container(
                  color: Colors.grey[900],
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _isStreaming ? null : _openSelectedCameras,
                          icon: const Icon(Icons.videocam),
                          label: Text(
                            _isStreaming
                                ? "Starting..."
                                : "Start Streaming (${selectedCameras.length})",
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            disabledBackgroundColor: Colors.grey,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: ElevatedButton(
                          onPressed: activeCameras.isEmpty ? null : _captureAll,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            shape: const CircleBorder(), // Macht den Button rund
                            padding: const EdgeInsets.all(16),
                          ),
                          child: const Icon(Icons.camera_alt, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: activeCameras.isEmpty ? null : _closeAllCameras,
                          icon: const Icon(Icons.stop),
                          label: const Text("Stop All"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            disabledBackgroundColor: Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCameraPreview(String cameraId) {
    final textureId = textureIds[cameraId];
    final camera =
        availableCameras.firstWhere((c) => c.id == cameraId, orElse: () {
      return CameraDevice(id: cameraId, name: "Camera $cameraId", facing: -1);
    });

    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue, width: 2),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            textureId != null
                ? Texture(textureId: textureId)
                : const Center(
                    child: CircularProgressIndicator(),
                  ),
            Positioned(
              bottom: 8,
              left: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  camera.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            //"Take-a-picture" Button (appears when lense is activated)
            Positioned(
              bottom: 8,
              right: 8,
              child: Material(
                shape: const CircleBorder(),
                child: IconButton(
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                  onPressed: () => _triggerCapture(cameraId),
                ),
              ),
            ),           
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _closeAllCameras();
    super.dispose();
  }
}