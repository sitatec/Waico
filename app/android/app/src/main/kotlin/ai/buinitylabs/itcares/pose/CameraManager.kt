package ai.buinitylabs.itcares.pose

import android.content.Context
import android.graphics.Bitmap
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Size
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import java.io.ByteArrayOutputStream
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Camera manager class that handles camera initialization, image capture,
 * and pose detection integration with MediaPipe for streaming to Flutter
 */
class CameraManager(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
    private val cameraStreamListener: CameraStreamListener
) : PoseLandmarkerHelper.LandmarkerListener {

    private var cameraProvider: ProcessCameraProvider? = null
    private var imageAnalyzer: ImageAnalysis? = null
    private var camera: Camera? = null
    private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null
    
    private var poseLandmarkerHelper: PoseLandmarkerHelper? = null
    private var isFrontCamera = false
    private var isShuttingDown = false
    
    // Performance tracking
    private var lastFrameTime = 0L
    private var frameCount = 0
    private var fpsCalculationInterval = 30 // Calculate FPS every 30 frames

    init {
        startBackgroundThread()
        initializePoseLandmarker()
    }

    /**
     * Starts background thread for camera operations
     */
    private fun startBackgroundThread() {
        backgroundThread = HandlerThread("CameraBackground").also { it.start() }
        backgroundHandler = Handler(backgroundThread!!.looper)
    }

    /**
     * Stops background thread
     */
    private fun stopBackgroundThread() {
        backgroundThread?.quitSafely()
        try {
            backgroundThread?.join()
            backgroundThread = null
            backgroundHandler = null
        } catch (e: InterruptedException) {
            Log.e(TAG, "Error stopping background thread", e)
        }
    }

    /**
     * Initialize the pose landmarker helper
     */
    private fun initializePoseLandmarker() {
        backgroundHandler?.post {
            try {
                poseLandmarkerHelper = PoseLandmarkerHelper(
                    context = context,
                    runningMode = com.google.mediapipe.tasks.vision.core.RunningMode.LIVE_STREAM,
                    poseLandmarkerHelperListener = this@CameraManager
                )
            } catch (e: Exception) {
                Log.e(TAG, "Error initializing pose landmarker", e)
                cameraStreamListener.onError("Failed to initialize pose detection: ${e.message}")
            }
        }
    }

    /**
     * Start camera with pose detection
     */
    fun startCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(context)
        cameraProviderFuture.addListener({
            try {
                cameraProvider = cameraProviderFuture.get()
                bindCameraUseCases()
            } catch (e: Exception) {
                Log.e(TAG, "Error starting camera", e)
                cameraStreamListener.onError("Failed to start camera: ${e.message}")
            }
        }, ContextCompat.getMainExecutor(context))
    }

    /**
     * Stop camera and cleanup resources
     */
    fun stopCamera() {
        // Set shutdown flag to prevent new frames from being processed
        isShuttingDown = true
        
        // Give a small delay to allow any pending frames to be processed
        try {
            Thread.sleep(100)
        } catch (e: InterruptedException) {
            // Ignore
        }
        
        // Stop pose detection first
        poseLandmarkerHelper?.clearPoseLandmarker()
        
        // Unbind camera use cases
        cameraProvider?.unbindAll()
        camera = null
        
        // Cleanup executors
        cameraExecutor.shutdown()
        stopBackgroundThread()
    }

    /**
     * Switch between front and back camera
     */
    fun switchCamera() {
        isFrontCamera = !isFrontCamera
        bindCameraUseCases()
    }

    /**
     * Bind camera use cases for image analysis
     */
    private fun bindCameraUseCases() {
        val cameraProvider = cameraProvider ?: return

        try {
            // Unbind use cases before rebinding
            cameraProvider.unbindAll()

            // Select camera
            val cameraSelector = if (isFrontCamera) {
                CameraSelector.DEFAULT_FRONT_CAMERA
            } else {
                CameraSelector.DEFAULT_BACK_CAMERA
            }

            // Set up image analysis use case
            imageAnalyzer = ImageAnalysis.Builder()
                .setTargetResolution(Size(640, 480)) // Optimize for performance
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
                .build()

            // Set analyzer
            imageAnalyzer?.setAnalyzer(cameraExecutor) { imageProxy ->
                analyzeImage(imageProxy)
            }

            // Bind use cases to camera
            camera = cameraProvider.bindToLifecycle(
                lifecycleOwner,
                cameraSelector,
                imageAnalyzer
            )

        } catch (e: Exception) {
            Log.e(TAG, "Error binding camera use cases", e)
            cameraStreamListener.onError("Failed to bind camera: ${e.message}")
        }
    }

    /**
     * Analyze image and perform pose detection
     */
    private fun analyzeImage(imageProxy: ImageProxy) {
        // Check if we're shutting down
        if (isShuttingDown) {
            imageProxy.close()
            return
        }
        
        try {
            // Calculate FPS
            calculateFPS()
            
            // Convert ImageProxy to Bitmap for streaming to Flutter
            val bitmap = imageProxyToBitmap(imageProxy)
            
            // Stream camera image to Flutter
            cameraStreamListener.onCameraFrame(bitmap)
            
            // Perform pose detection (this will close the imageProxy)
            poseLandmarkerHelper?.detectLiveStream(imageProxy, isFrontCamera)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error analyzing image", e)
            // Ensure ImageProxy is always closed to prevent memory leaks
            try {
                imageProxy.close()
            } catch (closeException: Exception) {
                Log.e(TAG, "Error closing ImageProxy", closeException)
            }
        }
    }

    /**
     * Convert ImageProxy to Bitmap
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

                // Rewind buffers so they can be read again by PoseLandmarkerHelper
                yBuffer.rewind()
                uBuffer.rewind()
                vBuffer.rewind()

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
                
                // Rewind the buffer so it can be read again by PoseLandmarkerHelper
                buffer.rewind()

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
     * Calculate and log FPS for performance monitoring
     */
    private fun calculateFPS() {
        frameCount++
        if (frameCount % fpsCalculationInterval == 0) {
            val currentTime = System.currentTimeMillis()
            if (lastFrameTime > 0) {
                val timeDiff = currentTime - lastFrameTime
                val fps = (fpsCalculationInterval * 1000f) / timeDiff
                Log.d(TAG, "Camera FPS: ${"%.1f".format(fps)}")
            }
            lastFrameTime = currentTime
        }
    }

    // PoseLandmarkerHelper.LandmarkerListener implementation
    override fun onError(error: String, errorCode: Int) {
        Log.e(TAG, "Pose detection error: $error (Code: $errorCode)")
        cameraStreamListener.onError("Pose detection error: $error")
    }

    override fun onResults(resultBundle: PoseLandmarkerHelper.ResultBundle) {
        try {
            // Stream pose landmarks to Flutter
            cameraStreamListener.onPoseLandmarks(resultBundle)
        } catch (e: Exception) {
            Log.e(TAG, "Error processing pose results", e)
        }
    }

    /**
     * Interface for camera stream events
     */
    interface CameraStreamListener {
        fun onCameraFrame(bitmap: Bitmap)
        fun onPoseLandmarks(resultBundle: PoseLandmarkerHelper.ResultBundle)
        fun onError(error: String)
    }

    companion object {
        private const val TAG = "CameraManager"
    }
}
