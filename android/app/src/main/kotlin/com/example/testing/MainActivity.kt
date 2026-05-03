package com.example.testing

import android.content.Context
import android.hardware.camera2.*
import android.os.Handler
import android.os.HandlerThread
import android.util.Size
import android.view.Surface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.app/camera"
    
    private val cameraDevices = mutableMapOf<String, CameraDevice>()
    private val captureSessions = mutableMapOf<String, CameraCaptureSession>()
    private val textureEntries = mutableMapOf<String, io.flutter.view.TextureRegistry.SurfaceTextureEntry>()
    
    private val threads = mutableMapOf<String, HandlerThread>()
    private val handlers = mutableMapOf<String, Handler>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            val manager = getSystemService(Context.CAMERA_SERVICE) as CameraManager

            when (call.method) {
                "openCamera" -> {
                    val cameraId = call.argument<String>("cameraId") ?: "0"
                
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

                        manager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                            override fun onOpened(camera: CameraDevice) {
                                cameraDevices[cameraId] = camera
                                
                                val builder = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                                builder.addTarget(surface)

                                camera.createCaptureSession(listOf(surface), object : CameraCaptureSession.StateCallback() {
                                    override fun onConfigured(session: CameraCaptureSession) {
                                        captureSessions[cameraId] = session
                                        builder.set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)

                                        session.setRepeatingRequest(builder.build(), null, handler)
                                        runOnUiThread { result.success(entry.id()) }
                                    }
                                    override fun onConfigureFailed(s: CameraCaptureSession) {
                                        runOnUiThread { result.error("FAIL", "Session Failed", null) }
                                    }
                                }, handler)
                            }
                            override fun onDisconnected(c: CameraDevice) { closeCamera(cameraId) }
                            override fun onError(c: CameraDevice, e: Int) { closeCamera(cameraId) }
                        }, handler)

                    } catch (e: Exception) {
                        result.error("ERR", e.message, null)
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
        try {
            captureSessions[id]?.stopRepeating()
            captureSessions[id]?.close()
        } catch (e: Exception) { }
        captureSessions.remove(id)

        try {
            cameraDevices[id]?.close()
        } catch (e: Exception) { }
        cameraDevices.remove(id)

        val entry = textureEntries[id]
        if (entry != null) {
            runOnUiThread {
                try {
                    entry.release()
                } catch (e: Exception) { }
            }
            textureEntries.remove(id)
        }

        threads[id]?.quitSafely()
        threads.remove(id)
        handlers.remove(id)
    }

    private fun stopAll() {
        cameraDevices.keys.toList().forEach { closeCamera(it) }
    }
}