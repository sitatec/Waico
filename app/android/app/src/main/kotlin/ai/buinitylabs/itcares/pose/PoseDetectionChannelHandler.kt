package ai.buinitylabs.itcares.pose

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.lifecycle.LifecycleOwner
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleRegistry
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Platform channel handler for pose detection that manages communication
 * between Flutter and native Android pose detection functionality.
 * This handler coordinates pose detection and sends results to Dart.
 * Now includes direct camera management for pose detection.
 */
class PoseDetectionChannelHandler(
    private val context: Context
) : MethodChannel.MethodCallHandler, PoseLandmarkerHelper.LandmarkerListener, LifecycleOwner {

    private var poseLandmarkerHelper: PoseLandmarkerHelper? = null
    private var landmarkStreamSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var isInitialized = false

    // Camera components
    private var cameraProvider: ProcessCameraProvider? = null
    private var imageAnalyzer: ImageAnalysis? = null
    private var preview: Preview? = null
    private var camera: Camera? = null
    private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var isFrontCamera = false
    private var isCameraActive = false
    private var isShuttingDown = false
    
    // Preview surface holder for camera preview
    private var previewSurfaceProvider: Preview.SurfaceProvider? = null
    
    // Lifecycle management for camera
    private val lifecycleRegistry = LifecycleRegistry(this)

    // Performance tracking
    private var lastLandmarkTime = 0L
    private var landmarkFrameCount = 0

    init {
        lifecycleRegistry.currentState = Lifecycle.State.CREATED
        lifecycleRegistry.currentState = Lifecycle.State.STARTED
        lifecycleRegistry.currentState = Lifecycle.State.RESUMED
        initializePoseDetection()
    }

    /**
     * Initialize pose detection - handles errors gracefully
     */
    private fun initializePoseDetection() {
        try {
            // Reset lifecycle state when reinitializing (important after disposal)
            lifecycleRegistry.currentState = Lifecycle.State.CREATED
            lifecycleRegistry.currentState = Lifecycle.State.STARTED
            lifecycleRegistry.currentState = Lifecycle.State.RESUMED
            Log.d(TAG, "Lifecycle state reset to RESUMED for reinitialization")
            
            poseLandmarkerHelper = PoseLandmarkerHelper(
                context = context,
                runningMode = com.google.mediapipe.tasks.vision.core.RunningMode.LIVE_STREAM,
                poseLandmarkerHelperListener = this
            )
            isInitialized = true
            Log.i(TAG, "Pose detection initialized successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to initialize pose detection", e)
            poseLandmarkerHelper = null
            isInitialized = false
        }
    }

    /**
     * Get the pose landmarker helper (may be null if initialization failed)
     */
    fun getPoseLandmarkerHelper(): PoseLandmarkerHelper? = poseLandmarkerHelper

    /**
     * Check if pose detection is available
     */
    fun isPoseDetectionAvailable(): Boolean = isInitialized && poseLandmarkerHelper != null

    /**
     * Handle method calls from Flutter
     */
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "startCamera" -> {
                    startPoseDetection(result)
                }
                "stopCamera" -> {
                    stopPoseDetection(result)
                }
                "switchCamera" -> {
                    switchCamera(result)
                }
                "dispose" -> {
                    dispose(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error handling method call: ${call.method}", e)
            result.error("POSE_DETECTION_ERROR", "Error: ${e.message}", null)
        }
    }

    /**
     * Start pose detection
     */
    private fun startPoseDetection(result: MethodChannel.Result) {
        try {
            Log.i(TAG, "=== STARTING POSE DETECTION ===")
            Log.i(TAG, "Current state - isShuttingDown: $isShuttingDown, isCameraActive: $isCameraActive, isInitialized: $isInitialized")
            Log.i(TAG, "PoseLandmarkerHelper: ${poseLandmarkerHelper != null}, CameraProvider: ${cameraProvider != null}")
            Log.i(TAG, "CameraExecutor isShutdown: ${cameraExecutor.isShutdown}")
            
            // Reset shutdown flag when starting
            isShuttingDown = false
            
            // Reinitialize pose detection if needed
            if (!isPoseDetectionAvailable()) {
                Log.i(TAG, "Reinitializing pose detection...")
                initializePoseDetection()
            }
            
            if (!isPoseDetectionAvailable()) {
                Log.e(TAG, "Pose detection still not available after reinitialize")
                result.error("POSE_DETECTION_UNAVAILABLE", "Pose detection is not available", null)
                return
            }
            
            startCamera(result)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error starting pose detection", e)
            result.error("POSE_DETECTION_START_ERROR", "Failed to start pose detection: ${e.message}", null)
        }
    }

    /**
     * Start camera for pose detection
     */
    private fun startCamera(result: MethodChannel.Result) {
        Log.i(TAG, "=== STARTING CAMERA ===")
        Log.i(TAG, "isCameraActive: $isCameraActive, previewSurfaceProvider: ${previewSurfaceProvider != null}")
        
        if (isCameraActive) {
            Log.i(TAG, "Camera already active")
            result.success("Camera already active")
            return
        }
        
        // Create new executor if the old one was shutdown
        if (cameraExecutor.isShutdown) {
            cameraExecutor = Executors.newSingleThreadExecutor()
            Log.i(TAG, "Created new camera executor")
        }
        
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        cameraProviderFuture.addListener({
            try {
                cameraProvider = cameraProviderFuture.get()
                Log.i(TAG, "Got camera provider, binding use cases...")
                bindCameraUseCases()
                isCameraActive = true
                result.success("Camera started for pose detection")
                Log.i(TAG, "Camera started successfully for pose detection")
            } catch (e: Exception) {
                Log.e(TAG, "Error starting camera", e)
                result.error("CAMERA_START_ERROR", "Failed to start camera: ${e.message}", null)
            }
        }, ContextCompat.getMainExecutor(context))
    }

    /**
     * Bind camera use cases for pose detection
     */
    private fun bindCameraUseCases() {
        val cameraProvider = cameraProvider ?: return

        try {
            Log.i(TAG, "=== BINDING CAMERA USE CASES ===")
            Log.i(TAG, "previewSurfaceProvider: ${previewSurfaceProvider != null}")
            
            // Unbind use cases before rebinding
            cameraProvider.unbindAll()

            // Select camera
            val cameraSelector = if (isFrontCamera) {
                CameraSelector.DEFAULT_FRONT_CAMERA
            } else {
                CameraSelector.DEFAULT_BACK_CAMERA
            }

            // Get optimal resolution for the device
            Log.d(TAG, "Using 16:9 aspect ratio for optimal camera experience")

            // Set up preview with 16:9 aspect ratio
            preview = Preview.Builder()
                .setTargetAspectRatio(AspectRatio.RATIO_16_9)
                .build()

            // Set up image analysis for pose detection with the same aspect ratio
            imageAnalyzer = ImageAnalysis.Builder()
                .setTargetAspectRatio(AspectRatio.RATIO_16_9)
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                .build()

            // Connect pose detection
            imageAnalyzer?.setAnalyzer(cameraExecutor) { imageProxy ->
                // Log.d(TAG, "Received camera frame: ${imageProxy.width}x${imageProxy.height}")
                connectPoseDetection(imageProxy)
            }

            // Build use cases list
            val useCases = mutableListOf<UseCase>(imageAnalyzer!!)
            
            // Add preview if surface provider is available
            previewSurfaceProvider?.let { surfaceProvider ->
                try {
                    preview?.setSurfaceProvider(surfaceProvider)
                    useCases.add(preview!!)
                    Log.i(TAG, "Preview added to camera use cases with surface provider")
                } catch (e: Exception) {
                    Log.e(TAG, "Error setting surface provider", e)
                }
            } ?: run {
                Log.i(TAG, "No surface provider available, skipping preview")
            }

            // Bind use cases to lifecycle
            camera = cameraProvider.bindToLifecycle(
                this,
                cameraSelector,
                *useCases.toTypedArray()
            )

            Log.i(TAG, "Camera bound successfully with ${useCases.size} use cases")

        } catch (e: Exception) {
            Log.e(TAG, "Error binding camera use cases", e)
        }
    }

    /**
     * Set preview surface provider for camera preview
     */
    fun setPreviewSurfaceProvider(surfaceProvider: Preview.SurfaceProvider?) {
        Log.i(TAG, "=== SETTING PREVIEW SURFACE PROVIDER ===")
        Log.i(TAG, "New surface provider: ${surfaceProvider != null}, isCameraActive: $isCameraActive")
        previewSurfaceProvider = surfaceProvider
        // If camera is already active, rebind to include preview
        if (isCameraActive) {
            Log.i(TAG, "Camera is active, rebinding use cases to update preview")
            bindCameraUseCases()
        } else {
            Log.i(TAG, "Camera not active, surface provider will be used when camera starts")
        }
    }

    /**
     * Connect pose detection to camera frames
     */
    private fun connectPoseDetection(imageProxy: ImageProxy) {
        if (isShuttingDown || !isCameraActive) {
            imageProxy.close()
            return
        }
        
        try {
            // Check if pose detection is available
            if (poseLandmarkerHelper != null && isPoseDetectionAvailable()) {
                // Log.d(TAG, "Processing frame for pose detection")
                // Pass image to pose detection
                poseLandmarkerHelper?.detectLiveStream(imageProxy, isFrontCamera)
            } else {
                Log.w(TAG, "Pose detection not available, closing frame")
                // No pose detection available, just close the image
                imageProxy.close()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in pose detection", e)
            imageProxy.close()
        }
    }

    /**
     * Stop pose detection
     */
    private fun stopPoseDetection(result: MethodChannel.Result) {
        try {
            stopCamera()
            result.success("Pose detection stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping pose detection", e)
            result.error("POSE_DETECTION_STOP_ERROR", "Failed to stop pose detection: ${e.message}", null)
        }
    }

    /**
     * Stop camera
     */
    private fun stopCamera() {
        isShuttingDown = true
        isCameraActive = false
        
        // Small delay to allow pending frames to complete
        try {
            Thread.sleep(50)
        } catch (e: InterruptedException) {
            // Ignore
        }
        
        cameraProvider?.unbindAll()
        camera = null
        Log.d(TAG, "Camera stopped")
    }

    /**
     * Dispose method called from Flutter
     */
    private fun dispose(result: MethodChannel.Result) {
        try {
            Log.i(TAG, "=== DISPOSE CALLED FROM FLUTTER ===")
            cleanup()
            result.success("Resources disposed")
            Log.i(TAG, "Resources disposed via Flutter call")
        } catch (e: Exception) {
            Log.e(TAG, "Error disposing resources", e)
            result.error("DISPOSE_ERROR", "Failed to dispose resources: ${e.message}", null)
        }
    }

    /**
     * Switch between front and back camera
     */
    private fun switchCamera(result: MethodChannel.Result) {
        try {
            if (!isCameraActive) {
                result.error("CAMERA_NOT_ACTIVE", "Camera is not active", null)
                return
            }
            
            isFrontCamera = !isFrontCamera
            bindCameraUseCases()
            result.success("Camera switched successfully")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error switching camera", e)
            result.error("CAMERA_SWITCH_ERROR", "Failed to switch camera: ${e.message}", null)
        }
    }

    /**
     * Set landmark stream event sink
     */
    fun setLandmarkStreamSink(sink: EventChannel.EventSink?) {
        landmarkStreamSink = sink
    }

    // PoseLandmarkerHelper.LandmarkerListener implementation
    override fun onResults(resultBundle: PoseLandmarkerHelper.ResultBundle) {
        try {
            //Log.d(TAG, "Received pose detection results with ${resultBundle.results.size} poses")
            
            // Calculate FPS for landmarks
            calculateLandmarkFPS()

            // Convert pose landmarks to Flutter-friendly format
            val landmarksData = mutableListOf<Map<String, Any>>()
            
            resultBundle.results.forEach { result ->
                result.landmarks().forEach { landmarkList ->
                    val landmarks = mutableListOf<Map<String, Any>>()
                    landmarkList.forEach { landmark ->
                        landmarks.add(
                            mapOf(
                                "x" to landmark.x(),
                                "y" to landmark.y(),
                                "z" to landmark.z(),
                                "visibility" to (landmark.visibility().orElse(1.0f))
                            )
                        )
                    }
                    landmarksData.add(
                        mapOf(
                            "landmarks" to landmarks,
                            "worldLandmarks" to extractWorldLandmarks(result)
                        )
                    )
                }
            }

            val resultData = mapOf(
                "poses" to landmarksData,
                "inferenceTime" to resultBundle.inferenceTime,
                "imageWidth" to resultBundle.inputImageWidth,
                "imageHeight" to resultBundle.inputImageHeight,
                "timestamp" to System.currentTimeMillis()
            )

            // Log.d(TAG, "Sending pose data to Flutter: ${landmarksData.size} poses")

            // Send to Flutter on main thread
            mainHandler.post {
                landmarkStreamSink?.success(resultData)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing pose landmarks", e)
        }
    }

    override fun onError(error: String, errorCode: Int) {
        mainHandler.post {
            landmarkStreamSink?.error("POSE_DETECTION_ERROR", error, null)
        }
    }

    /**
     * Extract world landmarks from pose detection result
     */
    private fun extractWorldLandmarks(result: PoseLandmarkerResult): List<Map<String, Any>> {
        val worldLandmarks = mutableListOf<Map<String, Any>>()
        
        result.worldLandmarks().forEach { worldLandmarkList ->
            worldLandmarkList.forEach { worldLandmark ->
                worldLandmarks.add(
                    mapOf(
                        "x" to worldLandmark.x(),
                        "y" to worldLandmark.y(),
                        "z" to worldLandmark.z(),
                        "visibility" to (worldLandmark.visibility().orElse(1.0f))
                    )
                )
            }
        }
        
        return worldLandmarks
    }

    /**
     * Calculate FPS for landmark detection
     */
    private fun calculateLandmarkFPS() {
        landmarkFrameCount++
        if (landmarkFrameCount % 30 == 0) {
            val currentTime = System.currentTimeMillis()
            if (lastLandmarkTime > 0) {
                val timeDiff = currentTime - lastLandmarkTime
                val fps = (30 * 1000f) / timeDiff
                Log.d(TAG, "Landmark Detection FPS: ${"%.1f".format(fps)}")
            }
            lastLandmarkTime = currentTime
        }
    }

    /**
     * Cleanup resources
     */
    fun cleanup() {
        Log.i(TAG, "=== STARTING CLEANUP ===")
        Log.i(TAG, "Current state before cleanup - isShuttingDown: $isShuttingDown, isCameraActive: $isCameraActive, isInitialized: $isInitialized")
        Log.i(TAG, "PoseLandmarkerHelper: ${poseLandmarkerHelper != null}, CameraProvider: ${cameraProvider != null}")
        
        isShuttingDown = true
        stopCamera()
        landmarkStreamSink = null
        
        // Clear pose detection
        poseLandmarkerHelper?.clearPoseLandmarker()
        poseLandmarkerHelper = null
        isInitialized = false
        
        // Clear camera provider
        cameraProvider = null
        
        // Shutdown executor service safely
        if (!cameraExecutor.isShutdown) {
            cameraExecutor.shutdown()
            Log.i(TAG, "Camera executor shutdown")
        }
        
        lifecycleRegistry.currentState = Lifecycle.State.DESTROYED
        Log.i(TAG, "=== CLEANUP COMPLETED ===")
    }

    // LifecycleOwner implementation
    override val lifecycle: Lifecycle get() = lifecycleRegistry

    companion object {
        private const val TAG = "PoseDetectionChannelHandler"
    }
}
