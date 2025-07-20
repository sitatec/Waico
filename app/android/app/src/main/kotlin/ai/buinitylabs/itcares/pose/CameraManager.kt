package ai.buinitylabs.itcares.pose

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
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
     * Check if camera permission is granted
     */
    fun hasCameraPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED
    }

    /**
     * Start camera with pose detection
     */
    fun startCamera() {
        if (!hasCameraPermission()) {
            cameraStreamListener.onError("Camera permission not granted")
            return
        }

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
        cameraProvider?.unbindAll()
        camera = null
        poseLandmarkerHelper?.clearPoseLandmarker()
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
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
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
        try {
            // Calculate FPS
            calculateFPS()
            
            // Convert ImageProxy to Bitmap for streaming to Flutter
            val bitmap = imageProxyToBitmap(imageProxy)
            
            // Stream camera image to Flutter
            cameraStreamListener.onCameraFrame(bitmap)
            
            // Perform pose detection
            poseLandmarkerHelper?.detectLiveStream(imageProxy, isFrontCamera)
            
        } catch (e: Exception) {
            Log.e(TAG, "Error analyzing image", e)
            imageProxy.close()
        }
    }

    /**
     * Convert ImageProxy to Bitmap
     */
    private fun imageProxyToBitmap(imageProxy: ImageProxy): Bitmap {
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

        return android.graphics.BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
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
