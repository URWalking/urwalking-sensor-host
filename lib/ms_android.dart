import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';


class MultiCamScreen extends StatefulWidget {
  const MultiCamScreen({super.key});

  @override
  State<MultiCamScreen> createState() => _MultiCamScreenState();
}

class _MultiCamScreenState extends State<MultiCamScreen> {
  static const platform = MethodChannel('com.example.app/camera');

  int? _textureIdBack;
  int? _textureIdFront;

  // UI state to prevent multiple simultaneous startup attempts
  bool _isStarting = false;


  Future<void> _startCameras() async {
    // Method to initialize both cameras sequentially:
    // 1. Check Permissions
    // 2. Start Back Cam 
    // Cooldown 
    //4. Start Front Cam
    setState(() => _isStarting = true);

    try {
      var status = await Permission.camera.request();
      if (!status.isGranted) {
        debugPrint("amera permission denied by user.");
        return;
      }

      // Request the Back Camera (ID '0') from Native
      final int backId = await platform.invokeMethod('openCamera', {'cameraId': '0'});
      setState(() => _textureIdBack = backId);

      await Future.delayed(const Duration(milliseconds: 1000));

      // Request the Front Camera (ID '1')
      final int frontId = await platform.invokeMethod('openCamera', {'cameraId': '1'});
      setState(() => _textureIdFront = frontId);

    } on PlatformException catch (e) {
      debugPrint("Native Platform Error: ${e.message}");
    } catch (e) {
      debugPrint("General App Error: $e");
    } finally {
      //Release the loading state regardless of success/failure
      setState(() => _isStarting = false);
    }
  }



  // BUTTONS ---------------
 @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Native Dual Camera")),
      body: Column(
        children: [
          _buildCameraPreview(_textureIdBack, "Back Camera Off"),
          const Icon(Icons.swap_vert, color: Colors.blue),
          _buildCameraPreview(_textureIdFront, "Front Camera Off"),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isStarting ? null : _startCameras,
        label: Text(_isStarting ? "Starting..." : "Start Dual Stream"),
        icon: const Icon(Icons.videocam),
      ),
    );
  }

  Widget _buildCameraPreview(int? id, String placeholder) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: id != null
              ? Texture(textureId: id)
              : Center(child: Text(placeholder, style: const TextStyle(color: Colors.white))),
        ),
      ),
    );
  }

  @override
  void dispose() {
    platform.invokeMethod('closeCamera');
    super.dispose();
  }
}