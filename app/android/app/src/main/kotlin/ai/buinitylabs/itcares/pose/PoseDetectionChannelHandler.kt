package ai.buinitylabs.itcares.pose

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.lifecycle.LifecycleOwner
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Platform channel handler for pose detection that manages communication
 * between Flutter and native Android pose detection functionality.
 * This handler coordinates pose detection and sends results to Dart.
 * Camera display is now handled by Flutter camera package.
 */
class PoseDetectionChannelHandler(
    private val context: Context
) : MethodChannel.MethodCallHandler, PoseLandmarkerHelper.LandmarkerListener {

    private var poseLandmarkerHelper: PoseLandmarkerHelper? = null
    private var landmarkStreamSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var isInitialized = false

    // Performance tracking
    private var lastLandmarkTime = 0L
    private var landmarkFrameCount = 0

    init {
        initializePoseDetection()
    }

    /**
     * Initialize pose detection - handles errors gracefully
     */
    private fun initializePoseDetection() {
        try {
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
            if (!isPoseDetectionAvailable()) {
                result.error("POSE_DETECTION_UNAVAILABLE", "Pose detection is not available", null)
                return
            }
            // Pose detection is started when camera view connects to it
            // This just confirms the service is ready
            result.success("Pose detection service ready")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error starting pose detection", e)
            result.error("POSE_DETECTION_START_ERROR", "Failed to start pose detection: ${e.message}", null)
        }
    }

    /**
     * Stop pose detection
     */
    private fun stopPoseDetection(result: MethodChannel.Result) {
        try {
            // Stop any active pose detection
            poseLandmarkerHelper?.clearPoseLandmarker()
            result.success("Pose detection stopped")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping pose detection", e)
            result.error("POSE_DETECTION_STOP_ERROR", "Failed to stop pose detection: ${e.message}", null)
        }
    }

    /**
     * Switch between front and back camera - now handled by Flutter camera
     */
    private fun switchCamera(result: MethodChannel.Result) {
        try {
            // Camera switching is now handled on Flutter side
            result.success("Camera switching is handled by Flutter camera package")
        } catch (e: Exception) {
            Log.e(TAG, "Error in switch camera method", e)
            result.error("CAMERA_SWITCH_ERROR", "Switch camera method error: ${e.message}", null)
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

            // Send to Flutter on main thread
            mainHandler.post {
                landmarkStreamSink?.success(
                    mapOf(
                        "poses" to landmarksData,
                        "inferenceTime" to resultBundle.inferenceTime,
                        "imageWidth" to resultBundle.inputImageWidth,
                        "imageHeight" to resultBundle.inputImageHeight,
                        "timestamp" to System.currentTimeMillis()
                    )
                )
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
        landmarkStreamSink = null
        poseLandmarkerHelper = null
        isInitialized = false
    }

    companion object {
        private const val TAG = "PoseDetectionChannelHandler"
    }
}
