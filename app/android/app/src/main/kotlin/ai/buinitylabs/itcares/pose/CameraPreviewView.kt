package ai.buinitylabs.itcares.pose

import android.content.Context
import android.view.View
import androidx.camera.view.PreviewView
import io.flutter.plugin.platform.PlatformView

/**
 * Simple camera preview platform view that integrates with PoseDetectionChannelHandler
 */
class CameraPreviewView(
    context: Context,
    id: Int,
    creationParams: Map<String, Any>?,
    private val poseDetectionChannelHandler: PoseDetectionChannelHandler
) : PlatformView {

    companion object {
        private const val TAG = "CameraPreviewView"
    }

    private val previewView: PreviewView = PreviewView(context)

    init {
        android.util.Log.i(TAG, "=== PLATFORM VIEW CREATED ===")
        // Set up the preview view
        previewView.implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        
        // Connect the preview to the pose detection handler
        poseDetectionChannelHandler.setPreviewSurfaceProvider(previewView.surfaceProvider)
        android.util.Log.i(TAG, "Surface provider set on pose detection handler")
    }

    override fun getView(): View = previewView

    override fun dispose() {
        android.util.Log.i(TAG, "=== PLATFORM VIEW DISPOSED ===")
        // Disconnect preview from pose detection handler
        poseDetectionChannelHandler.setPreviewSurfaceProvider(null)
        android.util.Log.i(TAG, "Surface provider cleared from pose detection handler")
    }
}
