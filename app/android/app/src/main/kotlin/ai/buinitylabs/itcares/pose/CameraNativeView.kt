package ai.buinitylabs.itcares.pose

import android.content.Context
import android.util.Log
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import io.flutter.plugin.platform.PlatformView
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Headless camera for pose detection only - no preview display
 * Only handles camera stream for pose estimation, results sent via PoseDetectionChannelHandler
 */
class CameraNativeView(
    context: Context,
    id: Int,
    creationParams: Map<String, Any>?,
    private val poseDetectionChannelHandler: PoseDetectionChannelHandler
) : PlatformView, LifecycleOwner {

    private val invisibleView = android.view.View(context) // Invisible view for PlatformView
    private var cameraProvider: ProcessCameraProvider? = null
    private var imageAnalyzer: ImageAnalysis? = null
    private var camera: Camera? = null
    private var cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    
    private var isFrontCamera = false
    private var isShuttingDown = false
    
    // Lifecycle management for camera
    private val lifecycleRegistry = LifecycleRegistry(this)

    init {
        lifecycleRegistry.currentState = Lifecycle.State.CREATED
        
        // Set invisible view size
        invisibleView.layoutParams = android.view.ViewGroup.LayoutParams(1, 1)
        invisibleView.visibility = android.view.View.GONE
        
        startCamera()
    }

    private fun startCamera() {
        val cameraProviderFuture = ProcessCameraProvider.getInstance(invisibleView.context)
        cameraProviderFuture.addListener({
            try {
                cameraProvider = cameraProviderFuture.get()
                lifecycleRegistry.currentState = Lifecycle.State.STARTED
                lifecycleRegistry.currentState = Lifecycle.State.RESUMED
                bindCameraUseCases()
            } catch (e: Exception) {
                Log.e(TAG, "Error starting camera", e)
            }
        }, ContextCompat.getMainExecutor(invisibleView.context))
    }

    private fun stopCamera() {
        isShuttingDown = true
        
        // Small delay to allow pending frames to complete
        try {
            Thread.sleep(50)
        } catch (e: InterruptedException) {
            // Ignore
        }
        
        cameraProvider?.unbindAll()
        camera = null
        cameraExecutor.shutdown()
    }

    private fun bindCameraUseCases() {
        val cameraProvider = cameraProvider ?: return
        if (lifecycleRegistry.currentState != Lifecycle.State.RESUMED) {
            return
        }

        try {
            // Unbind use cases before rebinding
            cameraProvider.unbindAll()

            // Select camera
            val cameraSelector = if (isFrontCamera) {
                CameraSelector.DEFAULT_FRONT_CAMERA
            } else {
                CameraSelector.DEFAULT_BACK_CAMERA
            }

            // Set up image analysis for pose detection only
            imageAnalyzer = ImageAnalysis.Builder()
                .setTargetResolution(android.util.Size(640, 480))
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
                .build()

            // Connect pose detection
            imageAnalyzer?.setAnalyzer(cameraExecutor) { imageProxy ->
                connectPoseDetection(imageProxy)
            }

            // Bind only image analysis - no preview
            camera = cameraProvider.bindToLifecycle(
                this,
                cameraSelector,
                imageAnalyzer
            )

            Log.d(TAG, "Camera bound successfully for pose detection only")

        } catch (e: Exception) {
            Log.e(TAG, "Error binding camera use cases", e)
        }
    }

    /**
     * Connect pose detection to camera frames
     */
    private fun connectPoseDetection(imageProxy: ImageProxy) {
        if (isShuttingDown) {
            imageProxy.close()
            return
        }
        
        try {
            // Check if pose detection is available
            val poseLandmarker = poseDetectionChannelHandler.getPoseLandmarkerHelper()
            if (poseLandmarker != null && poseDetectionChannelHandler.isPoseDetectionAvailable()) {
                // Pass image to pose detection through the channel handler
                poseLandmarker.detectLiveStream(imageProxy, isFrontCamera)
            } else {
                // No pose detection available, just close the image
                imageProxy.close()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in pose detection", e)
            imageProxy.close()
        }
    }

    fun switchCamera() {
        isFrontCamera = !isFrontCamera
        bindCameraUseCases()
    }

    // PlatformView implementation - returns invisible view
    override fun getView(): android.view.View = invisibleView

    override fun dispose() {
        stopCamera()
        lifecycleRegistry.currentState = Lifecycle.State.DESTROYED
    }

    // LifecycleOwner implementation
    override val lifecycle: Lifecycle get() = lifecycleRegistry

    companion object {
        private const val TAG = "CameraNativeView"
    }
}
