package ai.buinitylabs.itcares.pose

import android.content.Context
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class CameraPreviewViewFactory(
    private val poseDetectionChannelHandler: PoseDetectionChannelHandler
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val creationParams = args as? Map<String, Any>
        return CameraPreviewView(context, viewId, creationParams, poseDetectionChannelHandler)
    }
}
