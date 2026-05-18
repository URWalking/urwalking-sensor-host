package com.example.urwalking_sensor_host

import android.content.Context
import android.hardware.camera2.*
import android.os.Handler
import android.os.HandlerThread
import android.view.Surface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.media.ImageReader
import android.graphics.ImageFormat
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.app/camera"

    private val cameraDevices = mutableMapOf<String, CameraDevice>()
    private val captureSessions = mutableMapOf<String, CameraCaptureSession>()
    private val textureEntries = mutableMapOf<String, io.flutter.view.TextureRegistry.SurfaceTextureEntry>()
    private val threads = mutableMapOf<String, HandlerThread>()
    private val handlers = mutableMapOf<String, Handler>()
    private val imageReaders = mutableMapOf<String, ImageReader>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                val manager = getSystemService(Context.CAMERA_SERVICE) as CameraManager

                when (call.method) {

                    "listCameras" -> {
                        try {
                            val cameraList = mutableListOf<Map<String, Any>>()
                            val allIds = manager.cameraIdList

                            android.util.Log.d("CAMERA_LIST", "Total camera IDs: ${allIds.size} → ${allIds.joinToString()}")

                            for (id in allIds) {
                                val chars = manager.getCameraCharacteristics(id)
                                val facing = chars.get(CameraCharacteristics.LENS_FACING) ?: -1

                                // Check if this is a logical multi-camera
                                val capabilities = chars.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES) ?: intArrayOf()
                                val isLogical = capabilities.contains(
                                    CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_LOGICAL_MULTI_CAMERA
                                )

                                val facingLabel = when (facing) {
                                    CameraCharacteristics.LENS_FACING_BACK -> "Back"
                                    CameraCharacteristics.LENS_FACING_FRONT -> "Front"
                                    CameraCharacteristics.LENS_FACING_EXTERNAL -> "External"
                                    else -> "Unknown"
                                }

                                val label = if (isLogical) "$facingLabel (Logical)" else facingLabel

                                android.util.Log.d("CAMERA_LIST", "  ID=$id facing=$facingLabel logical=$isLogical")

                                cameraList.add(mapOf(
                                    "id" to id,
                                    "name" to "Camera $id ($label)",
                                    "facing" to facing,
                                    "isLogical" to isLogical
                                ))

                                // Enumerate physical cameras behind logical cameras
                                if (isLogical && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                                    val physicalIds = chars.physicalCameraIds
                                    android.util.Log.d("CAMERA_LIST", "    Physical children: $physicalIds")

                                    for (physId in physicalIds) {
                                        // Only add if NOT already a top-level logical camera
                                        val physChars = manager.getCameraCharacteristics(physId)
                                        val physCapabilities = physChars.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES) ?: intArrayOf()
                                        val physIsLogical = physCapabilities.contains(
                                            CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES_LOGICAL_MULTI_CAMERA
                                        )
                                        // Skip if it's itself a logical camera (already in top-level list)
                                        if (physIsLogical) continue

                                        val physFacing = physChars.get(CameraCharacteristics.LENS_FACING) ?: -1
                                        val physFacingLabel = when (physFacing) {
                                            CameraCharacteristics.LENS_FACING_BACK -> "Back"
                                            CameraCharacteristics.LENS_FACING_FRONT -> "Front"
                                            else -> "External"
                                        }

                                        android.util.Log.d("CAMERA_LIST", "    Adding physical: ID=$physId facing=$physFacingLabel parentLogical=$id")

                                        cameraList.add(mapOf(
                                            "id" to physId,
                                            "name" to "Camera $physId ($physFacingLabel Physical)",
                                            "facing" to physFacing,
                                            "isLogical" to false,
                                            "parentLogicalId" to id  // Flutter side can use this info
                                        ))
                                    }
                                }
                            }
                            // After building cameraList, check which pairs can run concurrently
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                                try {
                                    val concurrentIds = manager.concurrentCameraIds  // Set<Set<String>>
                                    android.util.Log.d("CAMERA_LIST", "Concurrent-capable sets: $concurrentIds")
                                    // e.g. might return [{0, 1}, {2, 5}] etc.
                                } catch (e: Exception) {
                                    android.util.Log.w("CAMERA_LIST", "concurrentCameraIds not available", e)
                                }
                            }

                            result.success(cameraList)

                        } catch (e: Exception) {
                            android.util.Log.e("CAMERA_LIST", "Error", e)
                            result.error("ERR", e.message, null)
                        }

                    }

                    "openCamera" -> {
                        val cameraId = call.argument<String>("cameraId") ?: return@setMethodCallHandler
                        val manager2 = getSystemService(Context.CAMERA_SERVICE) as CameraManager
                        val allIds = manager2.cameraIdList.toSet()

                        // Determine if physical (not a top-level ID) and find its logical parent
                        val isPhysical = cameraId !in allIds
                        var logicalParentId = cameraId

                        if (isPhysical && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                            for (lid in allIds) {
                                val chars = manager2.getCameraCharacteristics(lid)
                                if (cameraId in chars.physicalCameraIds) {
                                    logicalParentId = lid
                                    break
                                }
                            }
                        }

                        android.util.Log.d("OPEN_CAM", "Opening cameraId=$cameraId isPhysical=$isPhysical logicalParent=$logicalParentId")

                        val thread = HandlerThread("CamThread-$cameraId").also { it.start() }
                        val handler = Handler(thread.looper)
                        threads[cameraId] = thread
                        handlers[cameraId] = handler

                        try {
                            val entry = flutterEngine.renderer.createSurfaceTexture()
                            val surfaceTexture = entry.surfaceTexture()
                            surfaceTexture.setDefaultBufferSize(640, 480)
                            val surface = Surface(surfaceTexture)
                            textureEntries[cameraId] = entry

                            //new pipe for different res
                            // NOTE: Resolution changed to 640x480 per team decision.
                            // Higher resolutions (e.g., 1920x1080) can still be used if required by the hardware.
                            val photoReader = ImageReader.newInstance(640, 480, ImageFormat.JPEG, 2) 
                            imageReaders[cameraId] = photoReader
                            val photoSurface = photoReader.surface

                            manager2.openCamera(logicalParentId, object : CameraDevice.StateCallback() {
                                override fun onOpened(camera: CameraDevice) {
                                    cameraDevices[cameraId] = camera
                                    val builder = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                                    builder.addTarget(surface)

                                    val sessionCallback = object : CameraCaptureSession.StateCallback() {
                                        override fun onConfigured(session: CameraCaptureSession) {
                                            captureSessions[cameraId] = session
                                            builder.set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
                                            try {
                                                session.setRepeatingRequest(builder.build(), null, handler)
                                                runOnUiThread { result.success(entry.id()) }
                                            } catch (e: Exception) {
                                                runOnUiThread { result.error("ERR", e.message, null) }
                                            }
                                        }
                                        override fun onConfigureFailed(s: CameraCaptureSession) {
                                            runOnUiThread { result.error("FAIL", "Session config failed for $cameraId", null) }
                                        }
                                    }

                                    if (isPhysical && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                                        val outputConfig = android.hardware.camera2.params.OutputConfiguration(surface)
                                        outputConfig.setPhysicalCameraId(cameraId)
                                        val sessionConfig = android.hardware.camera2.params.SessionConfiguration(
                                            android.hardware.camera2.params.SessionConfiguration.SESSION_REGULAR,
                                            listOf(outputConfig),
                                            mainExecutor,
                                            sessionCallback
                                        )
                                        camera.createCaptureSession(sessionConfig)
                                    } else {
                                        @Suppress("DEPRECATION")
                                        camera.createCaptureSession(listOf(surface, photoSurface), sessionCallback, handler)
                                    }
                                }

                                override fun onDisconnected(camera: CameraDevice) {
                                    android.util.Log.w("OPEN_CAM", "Camera $cameraId disconnected")
                                    // Close session first, then device, then quit thread
                                    try { captureSessions[cameraId]?.close() } catch (_: Exception) {}
                                    captureSessions.remove(cameraId)
                                    try { camera.close() } catch (_: Exception) {}
                                    cameraDevices.remove(cameraId)
                                    runOnUiThread {
                                        try { textureEntries[cameraId]?.release() } catch (_: Exception) {}
                                        textureEntries.remove(cameraId)
                                    }
                                    // Quit AFTER camera is fully closed to avoid dead thread warnings
                                    handler.postDelayed({
                                        threads[cameraId]?.quitSafely()
                                        threads.remove(cameraId)
                                        handlers.remove(cameraId)
                                    }, 200)
                                }

                                override fun onError(camera: CameraDevice, error: Int) {
                                    android.util.Log.e("OPEN_CAM", "Camera $cameraId error: $error")
                                    onDisconnected(camera)
                                    runOnUiThread { result.error("ERR", "Camera error $error", null) }
                                }
                            }, handler)

                        } catch (e: SecurityException) {
                            result.error("PERMISSION", "Camera permission missing", null)
                        } catch (e: Exception) {
                            result.error("ERR", e.message, null)
                        }
                    }
                    "takePicture" -> {
                        val cameraId = call.argument<String>("cameraId")
                        
                        if (cameraId != null) {
                            val session = captureSessions[cameraId]
                            val reader = imageReaders[cameraId]
                            val camera = cameraDevices[cameraId]
                            val handler = handlers[cameraId]

                            if (camera != null && session != null && reader != null && handler != null) {

                                //listener so the app knows what to do when the photo data arrives
                                reader.setOnImageAvailableListener({ readerL ->
                                    val image = readerL.acquireLatestImage()
                                    val buffer = image.planes[0].buffer
                                    val bytes = ByteArray(buffer.remaining())
                                    buffer.get(bytes)
                                    image.close()

                                    // Save to file
                                    val file = File(context.filesDir, "photo_${cameraId}_${System.currentTimeMillis()}.jpg")
                                    try {
                                        FileOutputStream(file).use { it.write(bytes) }
                                        runOnUiThread { result.success(file.absolutePath) }
                                    } catch (e: Exception) {
                                        runOnUiThread { result.error("WRITE_ERR", e.message, null) }
                                    }
                                }, handler)

                                //capture with high resolution
                                try {
                                    val captureBuilder = camera.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
                                    captureBuilder.addTarget(reader.surface)
                                    session.capture(captureBuilder.build(), null, handler)
                                } catch (e: Exception) {
                                    result.error("CAPTURE_ERR", e.message, null)
                                }
                            } else {
                                result.error("NOT_READY", "Camera $cameraId components not found", null)
                            }
                        } else {
                            result.error("INVALID_ARG", "Missing cameraId", null)
                        }
                    }

                    "closeCamera" -> {
                        stopAll()
                        result.success(null)
                    }
                }
            }
    }

    private fun closeCamera(id: String) {
        try { captureSessions[id]?.stopRepeating() } catch (_: Exception) {}
        try { captureSessions[id]?.close() } catch (_: Exception) {}
        captureSessions.remove(id)

        try { cameraDevices[id]?.close() } catch (_: Exception) {}
        cameraDevices.remove(id)

        runOnUiThread {
            try { textureEntries[id]?.release() } catch (_: Exception) {}
            textureEntries.remove(id)
        }

        // Delay quit so camera close callbacks don't post to a dead looper
        handlers[id]?.postDelayed({
            threads[id]?.quitSafely()
            threads.remove(id)
            handlers.remove(id)
        }, 300)
    }

    private fun stopAll() {
        cameraDevices.keys.toList().forEach { closeCamera(it) }
    }
}