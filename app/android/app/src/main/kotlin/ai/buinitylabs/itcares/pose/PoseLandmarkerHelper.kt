package ai.buinitylabs.itcares.pose

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageFormat
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.SystemClock
import android.util.Log
import androidx.annotation.VisibleForTesting
import androidx.camera.core.ImageProxy
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarker
import com.google.mediapipe.tasks.vision.poselandmarker.PoseLandmarkerResult
import java.io.ByteArrayOutputStream

/**
 * Helper class for MediaPipe Pose Landmarker that manages pose detection functionality.
 * Supports both single image processing and live stream processing modes.
 */
class PoseLandmarkerHelper(
    var minPoseDetectionConfidence: Float = DEFAULT_POSE_DETECTION_CONFIDENCE,
    var minPoseTrackingConfidence: Float = DEFAULT_POSE_TRACKING_CONFIDENCE,
    var minPosePresenceConfidence: Float = DEFAULT_POSE_PRESENCE_CONFIDENCE,
    var currentModel: Int = MODEL_POSE_LANDMARKER_FULL,
    var currentDelegate: Int = DELEGATE_CPU,
    var runningMode: RunningMode = RunningMode.LIVE_STREAM,
    val context: Context,
    // This listener is only used when running in RunningMode.LIVE_STREAM
    var poseLandmarkerHelperListener: LandmarkerListener? = null
) {

    // For this example this needs to be a var so it can be reset on changes.
    // If the Pose Landmarker will not change, a lazy val would be preferable.
    private var poseLandmarker: PoseLandmarker? = null
    private var isShuttingDown = false

    init {
        setupPoseLandmarker()
    }

    /**
     * Clears and closes the current pose landmarker instance
     */
    fun clearPoseLandmarker() {
        isShuttingDown = true
        poseLandmarker?.close()
        poseLandmarker = null
    }

    /**
     * Returns the running status of PoseLandmarkerHelper
     * @return true if the landmarker is closed/null, false otherwise
     */
    fun isClose(): Boolean {
        return poseLandmarker == null
    }

    /**
     * Initialize the Pose landmarker using current settings on the
     * thread that is using it. CPU can be used with Landmarker
     * that are created on the main thread and used on a background thread, but
     * the GPU delegate needs to be used on the thread that initialized the
     * Landmarker
     */
    fun setupPoseLandmarker() {
        // Reset shutdown flag when setting up
        isShuttingDown = false
        
        // Set general pose landmarker options
        val baseOptionBuilder = BaseOptions.builder()

        // Use the specified hardware for running the model. Default to CPU
        when (currentDelegate) {
            DELEGATE_CPU -> {
                baseOptionBuilder.setDelegate(Delegate.CPU)
            }
            DELEGATE_GPU -> {
                baseOptionBuilder.setDelegate(Delegate.GPU)
            }
        }

        val modelName =
            when (currentModel) {
                MODEL_POSE_LANDMARKER_FULL -> "pose_landmarker_full.task"
                MODEL_POSE_LANDMARKER_LITE -> "pose_landmarker_lite.task"
                MODEL_POSE_LANDMARKER_HEAVY -> "pose_landmarker_heavy.task"
                else -> "pose_landmarker_full.task"
            }

        baseOptionBuilder.setModelAssetPath(modelName)

        // Check if runningMode is consistent with poseLandmarkerHelperListener
        when (runningMode) {
            RunningMode.LIVE_STREAM -> {
                if (poseLandmarkerHelperListener == null) {
                    throw IllegalStateException(
                        "poseLandmarkerHelperListener must be set when runningMode is LIVE_STREAM."
                    )
                }
            }
            else -> {
                // no-op
            }
        }

        try {
            val baseOptions = baseOptionBuilder.build()
            // Create an option builder with base options and specific
            // options only use for Pose Landmarker.
            val optionsBuilder =
                PoseLandmarker.PoseLandmarkerOptions.builder()
                    .setBaseOptions(baseOptions)
                    .setMinPoseDetectionConfidence(minPoseDetectionConfidence)
                    .setMinTrackingConfidence(minPoseTrackingConfidence)
                    .setMinPosePresenceConfidence(minPosePresenceConfidence)
                    .setRunningMode(runningMode)

            // The ResultListener and ErrorListener only use for LIVE_STREAM mode.
            if (runningMode == RunningMode.LIVE_STREAM) {
                optionsBuilder
                    .setResultListener(this::returnLivestreamResult)
                    .setErrorListener(this::returnLivestreamError)
            }

            val options = optionsBuilder.build()
            poseLandmarker =
                PoseLandmarker.createFromOptions(context, options)
        } catch (e: IllegalStateException) {
            poseLandmarkerHelperListener?.onError(
                "Pose Landmarker failed to initialize. See error logs for details"
            )
            Log.e(TAG, "MediaPipe failed to load the task with error: ${e.message}")
        } catch (e: RuntimeException) {
            // This occurs if the model being used does not support GPU
            poseLandmarkerHelperListener?.onError(
                "Pose Landmarker failed to initialize. See error logs for details", 
                GPU_ERROR
            )
            Log.e(TAG, "Image classifier failed to load model with error: ${e.message}")
        }
    }

    /**
     * Convert the ImageProxy to MP Image and feed it to PoselandmakerHelper.
     * @param imageProxy The camera image to process
     * @param isFrontCamera Whether the image is from front camera (for mirroring)
     */
    fun detectLiveStream(
        imageProxy: ImageProxy,
        isFrontCamera: Boolean
    ) {
        // Check if we're shutting down
        if (isShuttingDown || poseLandmarker == null) {
            imageProxy.close()
            return
        }
        
        if (runningMode != RunningMode.LIVE_STREAM) {
            throw IllegalArgumentException(
                "Attempting to call detectLiveStream while not using RunningMode.LIVE_STREAM"
            )
        }
        
        try {
            val frameTime = SystemClock.uptimeMillis()

            // Get image properties before closing the ImageProxy
            val rotationDegrees = imageProxy.imageInfo.rotationDegrees
            val imageWidth = imageProxy.width
            val imageHeight = imageProxy.height

            // Copy out RGB bits from the frame to a bitmap buffer
            val bitmapBuffer = imageProxyToBitmap(imageProxy)
            imageProxy.close()

            val matrix = Matrix().apply {
                // Rotate the frame received from the camera to be in the same direction as it'll be shown
                postRotate(rotationDegrees.toFloat())

                // flip image if user use front camera
                if (isFrontCamera) {
                    postScale(
                        -1f,
                        1f,
                        imageWidth.toFloat(),
                        imageHeight.toFloat()
                    )
                }
            }
            val rotatedBitmap = Bitmap.createBitmap(
                bitmapBuffer, 0, 0, bitmapBuffer.width, bitmapBuffer.height,
                matrix, true
            )

            // Convert the input Bitmap object to an MPImage object to run inference
            val mpImage = BitmapImageBuilder(rotatedBitmap).build()

            detectAsync(mpImage, frameTime)
        } catch (e: Exception) {
            Log.e(TAG, "Error in detectLiveStream", e)
            // Ensure ImageProxy is always closed to prevent memory leaks
            try {
                imageProxy.close()
            } catch (closeException: Exception) {
                Log.e(TAG, "Error closing ImageProxy in detectLiveStream", closeException)
            }
        }
    }

    /**
     * Run pose landmark using MediaPipe Pose Landmarker API
     * @param mpImage The processed image for landmark detection
     * @param frameTime The timestamp of the frame
     */
    @VisibleForTesting
    fun detectAsync(mpImage: MPImage, frameTime: Long) {
        // Check if we're shutting down before calling MediaPipe
        if (isShuttingDown || poseLandmarker == null) {
            return
        }
        
        try {
            poseLandmarker?.detectAsync(mpImage, frameTime)
            // As we're using running mode LIVE_STREAM, the landmark result will
            // be returned in returnLivestreamResult function
        } catch (e: Exception) {
            Log.e(TAG, "Error in detectAsync", e)
        }
    }

    /**
     * Return the detection result to this PoseLandmarkerHelper's caller
     */
    private fun returnLivestreamResult(
        result: PoseLandmarkerResult,
        input: MPImage
    ) {
        val finishTimeMs = SystemClock.uptimeMillis()
        val inferenceTime = finishTimeMs - result.timestampMs()

        poseLandmarkerHelperListener?.onResults(
            ResultBundle(
                results = listOf(result),
                inferenceTime = inferenceTime,
                inputImageHeight = input.height,
                inputImageWidth = input.width,
            )
        )
    }

    /**
     * Return errors thrown during detection to this PoseLandmarkerHelper's caller
     */
    private fun returnLivestreamError(error: RuntimeException) {
        poseLandmarkerHelperListener?.onError(
            error.message ?: "An unknown error has occurred"
        )
    }

    /**
     * Convert ImageProxy to Bitmap - handles both YUV and RGBA formats
     */
    private fun imageProxyToBitmap(imageProxy: ImageProxy): Bitmap {
        return when (imageProxy.format) {
            ImageFormat.YUV_420_888 -> {
                // Handle YUV format (3 planes)
                val yBuffer = imageProxy.planes[0].buffer // Y
                val uBuffer = imageProxy.planes[1].buffer // U
                val vBuffer = imageProxy.planes[2].buffer // V

                val ySize = yBuffer.remaining()
                val uSize = uBuffer.remaining()
                val vSize = vBuffer.remaining()

                val nv21 = ByteArray(ySize + uSize + vSize)

                // U and V are swapped
                yBuffer.get(nv21, 0, ySize)
                vBuffer.get(nv21, ySize, vSize)
                uBuffer.get(nv21, ySize + vSize, uSize)

                val yuvImage = YuvImage(nv21, ImageFormat.NV21, imageProxy.width, imageProxy.height, null)
                val out = ByteArrayOutputStream()
                yuvImage.compressToJpeg(Rect(0, 0, yuvImage.width, yuvImage.height), 85, out)
                val imageBytes = out.toByteArray()
                android.graphics.BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
            }
            else -> {
                // Handle RGBA_8888 format (1 plane) - this is what we're currently using
                val buffer = imageProxy.planes[0].buffer
                val pixelStride = imageProxy.planes[0].pixelStride
                val rowStride = imageProxy.planes[0].rowStride
                val width = imageProxy.width
                val height = imageProxy.height

                // Create a byte array to hold the pixel data
                val bytes = ByteArray(buffer.remaining())
                buffer.get(bytes)

                // Create bitmap from the raw pixel data
                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                
                // If there's no row padding, we can copy directly
                if (rowStride == pixelStride * width) {
                    val pixelBuffer = java.nio.ByteBuffer.wrap(bytes)
                    bitmap.copyPixelsFromBuffer(pixelBuffer)
                } else {
                    // Handle row padding by copying row by row
                    val pixelArray = IntArray(width * height)
                    var srcIndex = 0
                    var dstIndex = 0
                    
                    for (row in 0 until height) {
                        for (col in 0 until width) {
                            val r = bytes[srcIndex].toInt() and 0xFF
                            val g = bytes[srcIndex + 1].toInt() and 0xFF
                            val b = bytes[srcIndex + 2].toInt() and 0xFF
                            val a = bytes[srcIndex + 3].toInt() and 0xFF
                            
                            pixelArray[dstIndex] = (a shl 24) or (r shl 16) or (g shl 8) or b
                            
                            srcIndex += pixelStride
                            dstIndex++
                        }
                        // Skip padding at the end of each row
                        srcIndex += rowStride - (pixelStride * width)
                    }
                    
                    bitmap.setPixels(pixelArray, 0, width, 0, 0, width, height)
                }
                
                bitmap
            }
        }
    }

    /**
     * Sets the landmarker listener for pose detection callbacks
     */
    fun setLandmarkerListener(listener: LandmarkerListener?) {
        poseLandmarkerHelperListener = listener
    }

    companion object {
        const val TAG = "PoseLandmarkerHelper"

        const val DELEGATE_CPU = 0
        const val DELEGATE_GPU = 1
        const val DEFAULT_POSE_DETECTION_CONFIDENCE = 0.5F
        const val DEFAULT_POSE_TRACKING_CONFIDENCE = 0.5F
        const val DEFAULT_POSE_PRESENCE_CONFIDENCE = 0.5F
        const val DEFAULT_NUM_POSES = 1
        const val OTHER_ERROR = 0
        const val GPU_ERROR = 1
        const val MODEL_POSE_LANDMARKER_FULL = 0
        const val MODEL_POSE_LANDMARKER_LITE = 1
        const val MODEL_POSE_LANDMARKER_HEAVY = 2
    }

    /**
     * Data class to hold pose detection results along with metadata
     */
    data class ResultBundle(
        val results: List<PoseLandmarkerResult>,
        val inferenceTime: Long,
        val inputImageHeight: Int,
        val inputImageWidth: Int,
    )

    /**
     * Interface for handling pose detection results and errors
     */
    interface LandmarkerListener {
        fun onError(error: String, errorCode: Int = OTHER_ERROR)
        fun onResults(resultBundle: ResultBundle)
    }
}
