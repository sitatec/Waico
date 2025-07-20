package ai.buinitylabs.itcares.pose

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.lifecycle.LifecycleOwner
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Platform channel handler for pose detection that manages communication
 * between Flutter and native Android pose detection functionality
 */
class PoseDetectionChannelHandler(
    private val lifecycleOwner: LifecycleOwner
) : MethodChannel.MethodCallHandler, CameraManager.CameraStreamListener {

    private var cameraManager: CameraManager? = null
    private var cameraStreamSink: EventChannel.EventSink? = null
    private var landmarkStreamSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Performance tracking
    private var lastCameraFrameTime = 0L
    private var lastLandmarkTime = 0L
    private var cameraFrameCount = 0
    private var landmarkFrameCount = 0

    /**
     * Handle method calls from Flutter
     */
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "startCamera" -> {
                    startCamera(result)
                }
                "stopCamera" -> {
                    stopCamera(result)
                }
                "switchCamera" -> {
                    switchCamera(result)
                }
                "checkCameraPermission" -> {
                    checkCameraPermission(result)
                }
                "updatePoseDetectionSettings" -> {
                    updatePoseDetectionSettings(call, result)
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
     * Start camera and pose detection
     */
    private fun startCamera(result: MethodChannel.Result) {
        try {
            if (cameraManager == null) {
                cameraManager = CameraManager(
                    context = lifecycleOwner as android.content.Context,
                    lifecycleOwner = lifecycleOwner,
                    cameraStreamListener = this
                )
            }
            
            if (!cameraManager!!.hasCameraPermission()) {
                result.error("PERMISSION_DENIED", "Camera permission not granted", null)
                return
            }

            cameraManager!!.startCamera()
            result.success("Camera started successfully")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error starting camera", e)
            result.error("CAMERA_START_ERROR", "Failed to start camera: ${e.message}", null)
        }
    }

    /**
     * Stop camera and cleanup resources
     */
    private fun stopCamera(result: MethodChannel.Result) {
        try {
            cameraManager?.stopCamera()
            cameraManager = null
            result.success("Camera stopped successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping camera", e)
            result.error("CAMERA_STOP_ERROR", "Failed to stop camera: ${e.message}", null)
        }
    }

    /**
     * Switch between front and back camera
     */
    private fun switchCamera(result: MethodChannel.Result) {
        try {
            cameraManager?.switchCamera()
            result.success("Camera switched successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error switching camera", e)
            result.error("CAMERA_SWITCH_ERROR", "Failed to switch camera: ${e.message}", null)
        }
    }

    /**
     * Check camera permission status
     */
    private fun checkCameraPermission(result: MethodChannel.Result) {
        try {
            val hasPermission = cameraManager?.hasCameraPermission() ?: false
            result.success(hasPermission)
        } catch (e: Exception) {
            Log.e(TAG, "Error checking camera permission", e)
            result.error("PERMISSION_CHECK_ERROR", "Failed to check permission: ${e.message}", null)
        }
    }

    /**
     * Update pose detection settings
     */
    private fun updatePoseDetectionSettings(call: MethodCall, result: MethodChannel.Result) {
        try {
            val minDetectionConfidence = call.argument<Double>("minDetectionConfidence")?.toFloat()
            val minTrackingConfidence = call.argument<Double>("minTrackingConfidence")?.toFloat()
            val minPresenceConfidence = call.argument<Double>("minPresenceConfidence")?.toFloat()
            val modelType = call.argument<Int>("modelType")
            val delegate = call.argument<Int>("delegate")

            // Note: Settings update would require recreating the PoseLandmarkerHelper
            // This is a placeholder for future implementation
            Log.d(TAG, "Pose detection settings update requested")
            result.success("Settings update noted (requires camera restart to apply)")
            
        } catch (e: Exception) {
            Log.e(TAG, "Error updating pose detection settings", e)
            result.error("SETTINGS_UPDATE_ERROR", "Failed to update settings: ${e.message}", null)
        }
    }

    /**
     * Set camera stream event sink
     */
    fun setCameraStreamSink(sink: EventChannel.EventSink?) {
        cameraStreamSink = sink
    }

    /**
     * Set landmark stream event sink
     */
    fun setLandmarkStreamSink(sink: EventChannel.EventSink?) {
        landmarkStreamSink = sink
    }

    // CameraManager.CameraStreamListener implementation
    override fun onCameraFrame(bitmap: Bitmap) {
        try {
            // Convert bitmap to byte array for streaming to Flutter
            val outputStream = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, 85, outputStream)
            val imageBytes = outputStream.toByteArray()

            // Calculate FPS for camera frames
            calculateCameraFPS()

            // Send to Flutter on main thread
            mainHandler.post {
                cameraStreamSink?.success(
                    mapOf(
                        "image" to imageBytes,
                        "width" to bitmap.width,
                        "height" to bitmap.height,
                        "timestamp" to System.currentTimeMillis()
                    )
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error processing camera frame", e)
        }
    }

    override fun onPoseLandmarks(resultBundle: PoseLandmarkerHelper.ResultBundle) {
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

    override fun onError(error: String) {
        mainHandler.post {
            cameraStreamSink?.error("POSE_DETECTION_ERROR", error, null)
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
     * Calculate FPS for camera frames
     */
    private fun calculateCameraFPS() {
        cameraFrameCount++
        if (cameraFrameCount % 30 == 0) {
            val currentTime = System.currentTimeMillis()
            if (lastCameraFrameTime > 0) {
                val timeDiff = currentTime - lastCameraFrameTime
                val fps = (30 * 1000f) / timeDiff
                Log.d(TAG, "Camera Stream FPS: ${"%.1f".format(fps)}")
            }
            lastCameraFrameTime = currentTime
        }
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
        cameraManager?.stopCamera()
        cameraManager = null
        cameraStreamSink = null
        landmarkStreamSink = null
    }

    companion object {
        private const val TAG = "PoseDetectionChannelHandler"
    }
}
