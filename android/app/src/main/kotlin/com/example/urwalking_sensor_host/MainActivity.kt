package com.example.urwalking_sensor_host

import android.content.Context
import android.hardware.camera2.*
import android.os.Handler
import android.os.HandlerThread
import android.view.Surface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.media.ImageReader
import android.graphics.ImageFormat
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES20
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Config
import com.google.ar.core.Session
import com.google.ar.core.SharedCamera
import java.util.EnumSet

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.urwalking_sensor_host/camera"

    private val cameraDevices = mutableMapOf<String, CameraDevice>()
    private val captureSessions = mutableMapOf<String, CameraCaptureSession>()
    private val textureEntries = mutableMapOf<String, io.flutter.view.TextureRegistry.SurfaceTextureEntry>()
    private val threads = mutableMapOf<String, HandlerThread>()
    private val handlers = mutableMapOf<String, Handler>()
    private val imageReaders = mutableMapOf<String, ImageReader>()
    private val fastCaptureExecutors = mutableMapOf<String, java.util.concurrent.ExecutorService>()
    private val fastCaptureLogWriters = mutableMapOf<String, java.io.BufferedWriter>()

    private var arSession: Session? = null
    private var arThread: HandlerThread? = null
    private var arHandler: Handler? = null
    private var arEventSink: EventChannel.EventSink? = null
    private var arEglDisplay: EGLDisplay? = null
    private var arEglContext: EGLContext? = null
    private var arEglSurface: EGLSurface? = null
    private var arSharedCamera: SharedCamera? = null
    private var arCameraId: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.example.urwalking_sensor_host/arpose")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    arEventSink = events
                }
                override fun onCancel(arguments: Any?) {
                    arEventSink = null
                }
            })

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
                            // Pipe concurrent-capable sets to Flutter so it can pick a valid combination.
                            val concurrentSets = mutableListOf<List<String>>()
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                                try {
                                    for (set in manager.concurrentCameraIds) {
                                        concurrentSets.add(set.toList())
                                    }
                                    android.util.Log.d("CAMERA_LIST", "Concurrent-capable sets: $concurrentSets")
                                } catch (e: Exception) {
                                    android.util.Log.w("CAMERA_LIST", "concurrentCameraIds not available", e)
                                }
                            }

                            result.success(mapOf(
                                "cameras" to cameraList,
                                "concurrentSets" to concurrentSets,
                            ))

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
                            val photoReader = ImageReader.newInstance(640, 480, ImageFormat.JPEG, 5)
                            imageReaders[cameraId] = photoReader
                            val photoSurface = photoReader.surface

                            manager2.openCamera(logicalParentId, object : CameraDevice.StateCallback() {
                                override fun onOpened(camera: CameraDevice) {
                                    cameraDevices[cameraId] = camera
                                    val builder = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                                    builder.addTarget(surface)

                                    val sessionCallback = object : CameraCaptureSession.StateCallback() {
                                        override fun onConfigured(session: CameraCaptureSession) {
                                            android.util.Log.d("OPEN_CAM", "onConfigured OK for $cameraId")
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
                                            android.util.Log.e("OPEN_CAM", "onConfigureFailed for $cameraId")
                                            runOnUiThread { result.error("FAIL", "Session config failed for $cameraId", null) }
                                        }
                                    }

                                    if (isPhysical && android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                                        val previewConfig = android.hardware.camera2.params.OutputConfiguration(surface).apply {
                                            setPhysicalCameraId(cameraId)
                                        }
                                        val readerConfig = android.hardware.camera2.params.OutputConfiguration(photoSurface).apply {
                                            setPhysicalCameraId(cameraId)
                                        }
                                        val sessionConfig = android.hardware.camera2.params.SessionConfiguration(
                                            android.hardware.camera2.params.SessionConfiguration.SESSION_REGULAR,
                                            listOf(previewConfig, readerConfig),
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

                    "getDownloadsPath" -> {
                        result.success(
                            android.os.Environment.getExternalStoragePublicDirectory(
                                android.os.Environment.DIRECTORY_DOWNLOADS
                            ).absolutePath
                        )
                    }

                    "setKeepScreenOn" -> {
                        val on = call.argument<Boolean>("on") ?: false
                        runOnUiThread {
                            if (on) {
                                window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(null)
                    }

                    "startFastCapture" -> {
                        val cameraId = call.argument<String>("cameraId") ?: return@setMethodCallHandler result.error("INVALID_ARG", "Missing cameraId", null)
                        val outputDir = call.argument<String>("outputDir") ?: return@setMethodCallHandler result.error("INVALID_ARG", "Missing outputDir", null)
                        android.util.Log.d("FastCapture", "start: cameraId=$cameraId dir=$outputDir")

                        val reader = imageReaders[cameraId] ?: return@setMethodCallHandler result.error("NOT_READY", "No reader for $cameraId", null)
                        val handler = handlers[cameraId] ?: return@setMethodCallHandler result.error("NOT_READY", "No handler for $cameraId", null)

                        val logFile = java.io.File(outputDir, "image_timestamps.csv")
                        val writer = logFile.bufferedWriter()
                        writer.write("phone_ts_ms,filename\n")
                        writer.flush()
                        fastCaptureLogWriters[cameraId] = writer

                        val executor = java.util.concurrent.Executors.newSingleThreadExecutor()
                        fastCaptureExecutors[cameraId] = executor

                        reader.setOnImageAvailableListener({ readerL ->
                            val image = readerL.acquireLatestImage()
                            if (image == null) {
                                android.util.Log.w("FastCapture", "acquireLatestImage returned null")
                                return@setOnImageAvailableListener
                            }
                            val ts = System.currentTimeMillis()
                            val buffer = image.planes[0].buffer
                            val bytes = ByteArray(buffer.remaining()).also { buffer.get(it) }
                            image.close()
                            val filename = "frame_${ts}.jpg"
                            android.util.Log.d("FastCapture", "image received: $filename (${bytes.size} bytes)")
                            executor.submit {
                                try {
                                    java.io.File(outputDir, filename).writeBytes(bytes)
                                    synchronized(writer) {
                                        writer.write("$ts,$filename\n")
                                        writer.flush()
                                    }
                                    android.util.Log.d("FastCapture", "wrote $filename")
                                } catch (e: Exception) {
                                    android.util.Log.e("FastCapture", "Write failed for $filename", e)
                                }
                            }
                        }, handler)

                        if (cameraId == arCameraId) {
                            // Already streaming continuously as part of the shared AR
                            // capture request; the listener swap above is all that's needed.
                            android.util.Log.d("FastCapture", "AR-shared camera $cameraId already streaming")
                            result.success(null)
                        } else {
                            val session = captureSessions[cameraId] ?: run {
                                android.util.Log.e("FastCapture", "NOT_READY: no session for $cameraId (sessions=${captureSessions.keys})")
                                return@setMethodCallHandler result.error("NOT_READY", "No session for $cameraId", null)
                            }
                            val camera = cameraDevices[cameraId] ?: return@setMethodCallHandler result.error("NOT_READY", "No camera for $cameraId", null)
                            try {
                                val req = camera.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                                    addTarget(reader.surface)
                                }.build()
                                session.setRepeatingRequest(req, null, handler)
                                android.util.Log.d("FastCapture", "setRepeatingRequest OK for $cameraId")
                                result.success(null)
                            } catch (e: Exception) {
                                android.util.Log.e("FastCapture", "setRepeatingRequest failed: ${e.message}")
                                result.error("CAPTURE_ERR", e.message, null)
                            }
                        }
                    }

                    "startArPose" -> {
                        try {
                            val availability = ArCoreApk.getInstance().checkAvailability(this)
                            if (availability == ArCoreApk.Availability.UNSUPPORTED_DEVICE_NOT_CAPABLE) {
                                result.error("NOT_SUPPORTED", "ARCore not supported on this device", null)
                                return@setMethodCallHandler
                            }
                            // Shared camera: ARCore and our own JPEG capture pipeline attach to the SAME CameraDevice/CameraCaptureSession so they can run concurrently.
                            // Two independent Camera2 clients fighting over the same physical camera was an issue before
                            val session = Session(this, EnumSet.of(Session.Feature.SHARED_CAMERA))
                            val config = Config(session).apply {
                                updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                                focusMode = Config.FocusMode.AUTO
                            }
                            session.configure(config)

                            val sharedCamera = session.sharedCamera
                            val cameraId = session.cameraConfig.cameraId
                            arSharedCamera = sharedCamera
                            arCameraId = cameraId

                            arThread = HandlerThread("ArThread").also { it.start() }
                            val handler = Handler(arThread!!.looper)
                            arHandler = handler
                            handlers[cameraId] = handler
                            threads[cameraId] = arThread!!

                            val photoReader = ImageReader.newInstance(640, 480, ImageFormat.JPEG, 5)
                            imageReaders[cameraId] = photoReader
                            // Drain frames by default so the continuously-running shared
                            // stream never stalls waiting on a reader nobody is consuming.
                            photoReader.setOnImageAvailableListener({ r -> r.acquireLatestImage()?.close() }, handler)

                            // Once session.resume() hands control to ARCore, ARCore builds
                            // its own repeating request internally and only targets surfaces
                            // it knows about. Without registering ours here, it silently
                            // drops our JPEG surface after the very first frame.
                            sharedCamera.setAppSurfaces(cameraId, listOf(photoReader.surface))

                            val deviceCallback = object : CameraDevice.StateCallback() {
                                override fun onOpened(camera: CameraDevice) {
                                    cameraDevices[cameraId] = camera

                                    val surfaceList = sharedCamera.arCoreSurfaces.toMutableList()
                                    surfaceList.add(photoReader.surface)

                                    val sessionCallback = object : CameraCaptureSession.StateCallback() {
                                        override fun onConfigured(captureSession: CameraCaptureSession) {
                                            captureSessions[cameraId] = captureSession
                                            try {
                                                val requestBuilder = camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD)
                                                for (surface in surfaceList) {
                                                    requestBuilder.addTarget(surface)
                                                }
                                                // One-time hand-off request. Once ARCore is resumed it drives the repeating request itself
                                                // the app must not call setRepeatingRequest again after this.
                                                captureSession.setRepeatingRequest(requestBuilder.build(), null, handler)

                                                // session.update() requires an active OpenGL ES context.
                                                // Create a minimal offscreen EGL context on the AR thread
                                                // so ARCore can access the GPU without a visible surface.
                                                val eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
                                                EGL14.eglInitialize(eglDisplay, IntArray(1), 0, IntArray(1), 0)
                                                val cfgAttribs = intArrayOf(
                                                    EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                                                    EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
                                                    EGL14.EGL_NONE
                                                )
                                                val eglCfgs = arrayOfNulls<EGLConfig>(1)
                                                EGL14.eglChooseConfig(eglDisplay, cfgAttribs, 0, eglCfgs, 0, 1, IntArray(1), 0)
                                                val ctxAttribs = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)
                                                val eglContext = EGL14.eglCreateContext(eglDisplay, eglCfgs[0]!!, EGL14.EGL_NO_CONTEXT, ctxAttribs, 0)
                                                val pbAttribs = intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE)
                                                val eglSurface = EGL14.eglCreatePbufferSurface(eglDisplay, eglCfgs[0]!!, pbAttribs, 0)
                                                EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)

                                                arEglDisplay = eglDisplay
                                                arEglContext = eglContext
                                                arEglSurface = eglSurface

                                                val texIds = IntArray(1)
                                                GLES20.glGenTextures(1, texIds, 0)
                                                session.setCameraTextureName(texIds[0])
                                                session.resume()
                                                arSession = session

                                                // ARCore needs a non-zero display geometry to run its internal tracking/depth pipeline, even without a visible
                                                // surface. Without this it logs "invalid width: 0" and fails to produce depth measurements.
                                                val display = (getSystemService(Context.DISPLAY_SERVICE) as android.hardware.display.DisplayManager)
                                                    .getDisplay(android.view.Display.DEFAULT_DISPLAY)
                                                val metrics = resources.displayMetrics
                                                session.setDisplayGeometry(display.rotation, metrics.widthPixels, metrics.heightPixels)

                                                val updateRunnable = object : Runnable {
                                                    override fun run() {
                                                        try {
                                                            val frame = arSession?.update() ?: run {
                                                                arHandler?.postDelayed(this, 33); return
                                                            }
                                                            val poseCamera = frame.camera
                                                            val pose = poseCamera.pose
                                                            val t = pose.translation
                                                            val q = pose.rotationQuaternion
                                                            val tracking = poseCamera.trackingState.name
                                                            val data = mapOf(
                                                                "tx" to t[0].toDouble(),
                                                                "ty" to t[1].toDouble(),
                                                                "tz" to t[2].toDouble(),
                                                                "qx" to q[0].toDouble(),
                                                                "qy" to q[1].toDouble(),
                                                                "qz" to q[2].toDouble(),
                                                                "qw" to q[3].toDouble(),
                                                                "tracking" to tracking
                                                            )
                                                            runOnUiThread { arEventSink?.success(data) }
                                                        } catch (_: Exception) {}
                                                        arHandler?.postDelayed(this, 33)
                                                    }
                                                }
                                                arHandler?.post(updateRunnable)

                                                runOnUiThread { result.success(cameraId) }
                                            } catch (e: Exception) {
                                                runOnUiThread { result.error("AR_ERR", e.message, null) }
                                            }
                                        }
                                        override fun onConfigureFailed(s: CameraCaptureSession) {
                                            android.util.Log.e("ArPose", "Shared capture session config failed")
                                            runOnUiThread { result.error("FAIL", "AR shared session config failed", null) }
                                        }
                                    }

                                    @Suppress("DEPRECATION")
                                    camera.createCaptureSession(
                                        surfaceList,
                                        sharedCamera.createARSessionStateCallback(sessionCallback, handler),
                                        handler
                                    )
                                }
                                override fun onDisconnected(camera: CameraDevice) {
                                    android.util.Log.w("ArPose", "AR camera $cameraId disconnected")
                                    cameraDevices.remove(cameraId)
                                }
                                override fun onError(camera: CameraDevice, error: Int) {
                                    android.util.Log.e("ArPose", "AR camera $cameraId error: $error")
                                    cameraDevices.remove(cameraId)
                                    runOnUiThread { result.error("ERR", "AR camera error $error", null) }
                                }
                            }

                            manager.openCamera(
                                cameraId,
                                sharedCamera.createARDeviceStateCallback(deviceCallback, handler),
                                handler
                            )
                        } catch (e: Exception) {
                            result.error("AR_ERR", e.message, null)
                        }
                    }

                    "stopArPose" -> {
                        stopArPoseAndCamera()
                        result.success(null)
                    }

                    "stopFastCapture" -> {
                        val cameraId = call.argument<String>("cameraId") ?: return@setMethodCallHandler result.error("INVALID_ARG", "Missing cameraId", null)

                        // The AR camera's repeating request is owned by ARCore once shared;
                        // stopping it here would kill AR tracking too. Just drain frames instead of writing them, so the stream keeps flowing.
                        if (cameraId == arCameraId) {
                            imageReaders[cameraId]?.setOnImageAvailableListener(
                                { r -> r.acquireLatestImage()?.close() }, handlers[cameraId]
                            )
                        } else {
                            try { captureSessions[cameraId]?.stopRepeating() } catch (_: Exception) {}
                            imageReaders[cameraId]?.setOnImageAvailableListener(null, null)
                        }

                        fastCaptureExecutors[cameraId]?.let {
                            it.shutdown()
                            it.awaitTermination(5, java.util.concurrent.TimeUnit.SECONDS)
                        }
                        fastCaptureExecutors.remove(cameraId)

                        try { fastCaptureLogWriters[cameraId]?.close() } catch (_: Exception) {}
                        fastCaptureLogWriters.remove(cameraId)

                        result.success(null)
                    }
                }
            }
    }

    private fun stopArPoseAndCamera() {
        arHandler?.removeCallbacksAndMessages(null)
        try { arSession?.pause() } catch (_: Exception) {}
        try { arSession?.close() } catch (_: Exception) {}
        arSession = null

        val id = arCameraId
        if (id != null) {
            fastCaptureExecutors[id]?.let { it.shutdown() }
            fastCaptureExecutors.remove(id)
            try { fastCaptureLogWriters[id]?.close() } catch (_: Exception) {}
            fastCaptureLogWriters.remove(id)

            try { captureSessions[id]?.close() } catch (_: Exception) {}
            captureSessions.remove(id)
            try { cameraDevices[id]?.close() } catch (_: Exception) {}
            cameraDevices.remove(id)
            try { imageReaders[id]?.close() } catch (_: Exception) {}
            imageReaders.remove(id)
            handlers.remove(id)
            threads.remove(id)
        }
        arCameraId = null
        arSharedCamera = null

        try { arEglSurface?.let { EGL14.eglDestroySurface(arEglDisplay, it) } } catch (_: Exception) {}
        try { arEglContext?.let { EGL14.eglDestroyContext(arEglDisplay, it) } } catch (_: Exception) {}
        try { arEglDisplay?.let { EGL14.eglTerminate(it) } } catch (_: Exception) {}
        arEglSurface = null
        arEglContext = null
        arEglDisplay = null

        arThread?.quitSafely()
        arThread = null
        arHandler = null
    }

    private fun closeCamera(id: String) {
        if (id == arCameraId) {
            stopArPoseAndCamera()
            return
        }
        imageReaders[id]?.setOnImageAvailableListener(null, null)
        fastCaptureExecutors[id]?.let { it.shutdown() }
        fastCaptureExecutors.remove(id)
        try { fastCaptureLogWriters[id]?.close() } catch (_: Exception) {}
        fastCaptureLogWriters.remove(id)

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
