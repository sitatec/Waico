package ai.buinitylabs.waico

import ai.buinitylabs.itcares.pose.PoseDetectionChannelHandler
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    
    private lateinit var poseDetectionChannelHandler: PoseDetectionChannelHandler
    
    companion object {
        private const val POSE_DETECTION_CHANNEL = "ai.buinitylabs.waico/pose_detection"
        private const val LANDMARK_STREAM_CHANNEL = "ai.buinitylabs.waico/landmark_stream"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // Always initialize pose detection channel handler
        // It will handle any initialization issues internally
        poseDetectionChannelHandler = PoseDetectionChannelHandler(this)
        
        android.util.Log.i("MainActivity", "Pose detection channel handler initialized")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register method channel for pose detection controls
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            POSE_DETECTION_CHANNEL
        ).setMethodCallHandler(poseDetectionChannelHandler)
        
        // Register event channel for landmark stream
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LANDMARK_STREAM_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                poseDetectionChannelHandler.setLandmarkStreamSink(events)
            }
            
            override fun onCancel(arguments: Any?) {
                poseDetectionChannelHandler.setLandmarkStreamSink(null)
            }
        })
        
        android.util.Log.i("MainActivity", "All channels registered successfully")
    }

    override fun onDestroy() {
        super.onDestroy()
        poseDetectionChannelHandler.cleanup()
    }
}
