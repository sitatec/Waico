import Flutter
import UIKit
import AVFoundation

class PoseDetectionChannelHandler: NSObject {
    private let poseDetectionChannel: FlutterMethodChannel
    private let landmarkStreamChannel: FlutterEventChannel
    
    private var landmarkEventSink: FlutterEventSink?
    
    private var cameraManager: CameraManager?
    private var poseLandmarkerService: PoseLandmarkerService?
    
    private var frameCount = 0
    private var lastFrameTime: CFTimeInterval = 0
    
    init(registrar: FlutterPluginRegistrar) {
        self.poseDetectionChannel = FlutterMethodChannel(
            name: "ai.buinitylabs.waico/pose_detection",
            binaryMessenger: registrar.messenger()
        )
        
        self.landmarkStreamChannel = FlutterEventChannel(
            name: "ai.buinitylabs.waico/landmark_stream",
            binaryMessenger: registrar.messenger()
        )
        
        super.init()
        
        setupChannels()
    }
    
    private func setupChannels() {
        poseDetectionChannel.setMethodCallHandler { [weak self] (call, result) in
            self?.handleMethodCall(call: call, result: result)
        }
        
        landmarkStreamChannel.setStreamHandler(LandmarkStreamHandler { [weak self] eventSink in
            self?.landmarkEventSink = eventSink
        })
    }
    
    private func handleMethodCall(call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startCamera":
            startCamera(result: result)
        case "stopCamera":
            stopCamera(result: result)
        case "switchCamera":
            switchCamera(result: result)
        case "checkCameraPermission":
            checkCameraPermission(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func startCamera(result: @escaping FlutterResult) {
        // Initialize camera manager if needed
        if cameraManager == nil {
            cameraManager = CameraManager()
            cameraManager?.delegate = self
        }
        
        // Check permission
        guard cameraManager?.checkCameraPermission() == true else {
            cameraManager?.requestCameraPermission { [weak self] granted in
                if granted {
                    self?.startCameraSession(result: result)
                } else {
                    result(FlutterError(code: "PERMISSION_DENIED", message: "Camera permission not granted", details: nil))
                }
            }
            return
        }
        
        startCameraSession(result: result)
    }
    
    private func startCameraSession(result: @escaping FlutterResult) {
        // Initialize pose landmarker
        guard let modelPath = getModelPath() else {
            result(FlutterError(code: "MODEL_NOT_FOUND", message: "Pose landmarker model not found", details: nil))
            return
        }
        
        poseLandmarkerService = PoseLandmarkerService.liveStreamPoseLandmarkerService(
            modelPath: modelPath,
            liveStreamDelegate: self
        )
        
        guard poseLandmarkerService != nil else {
            result(FlutterError(code: "POSE_LANDMARKER_INIT_FAILED", message: "Failed to initialize pose landmarker", details: nil))
            return
        }
        
        // Start camera
        cameraManager?.startSession()
        result("Camera started successfully")
    }
    
    private func stopCamera(result: @escaping FlutterResult) {
        cameraManager?.stopSession()
        poseLandmarkerService?.close()
        poseLandmarkerService = nil
        result("Camera stopped successfully")
    }
    
    private func switchCamera(result: @escaping FlutterResult) {
        guard cameraManager?.isRunning == true else {
            result(FlutterError(code: "CAMERA_NOT_RUNNING", message: "Camera is not running", details: nil))
            return
        }
        
        cameraManager?.switchCamera()
        result("Camera switched successfully")
    }
    
    private func checkCameraPermission(result: @escaping FlutterResult) {
        let hasPermission = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        result(hasPermission)
    }
    
    private func getModelPath() -> String? {
        // Try to find the pose landmarker model in the app bundle
        let modelNames = ["pose_landmarker_full", "pose_landmarker_lite", "pose_landmarker_heavy"]
        
        for modelName in modelNames {
            if let path = Bundle.main.path(forResource: modelName, ofType: "task") {
                return path
            }
        }
        
        return nil
    }
}

// MARK: - CameraManagerDelegate
extension PoseDetectionChannelHandler: CameraManagerDelegate {
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer, orientation: UIImage.Orientation) {
        // Calculate frame timestamp
        let currentTime = CACurrentMediaTime()
        let timestampMs = Int(currentTime * 1000)
        
        // Perform pose detection only - no image streaming
        poseLandmarkerService?.detectAsync(
            sampleBuffer: sampleBuffer,
            orientation: orientation,
            timeStamps: timestampMs
        )
        
        // Calculate FPS for performance monitoring
        frameCount += 1
        if frameCount % 30 == 0 {
            if lastFrameTime > 0 {
                let timeDiff = currentTime - lastFrameTime
                let fps = 30.0 / timeDiff
                print("Pose Detection FPS: \(String(format: "%.1f", fps))")
            }
            lastFrameTime = currentTime
        }
    }
    
    func cameraManager(_ manager: CameraManager, didFailWithError error: Error) {
        let errorMessage = "Camera error: \(error.localizedDescription)"
        
        DispatchQueue.main.async { [weak self] in
            self?.landmarkEventSink?(FlutterError(code: "CAMERA_ERROR", message: errorMessage, details: nil))
        }
    }
}

// MARK: - PoseLandmarkerServiceLiveStreamDelegate
extension PoseDetectionChannelHandler: PoseLandmarkerServiceLiveStreamDelegate {
    func poseLandmarkerService(_ poseLandmarkerService: PoseLandmarkerService, didFinishDetection result: ResultBundle?, error: Error?) {
        
        if let error = error {
            let errorMessage = "Pose detection error: \(error.localizedDescription)"
            DispatchQueue.main.async { [weak self] in
                self?.landmarkEventSink?(FlutterError(code: "POSE_DETECTION_ERROR", message: errorMessage, details: nil))
            }
            return
        }
        
        guard let result = result,
              let poseLandmarkerResult = result.poseLandmarkerResults.first,
              let poseLandmarkerResult = poseLandmarkerResult else {
            return
        }
        
        // Convert pose landmarks to Flutter format
        var poses: [[String: Any]] = []
        
        for (poseIndex, landmarks) in poseLandmarkerResult.landmarks.enumerated() {
            var landmarksArray: [[String: Any]] = []
            var worldLandmarksArray: [[String: Any]] = []
            
            // Convert landmarks
            for landmark in landmarks {
                let landmarkDict: [String: Any] = [
                    "x": landmark.x,
                    "y": landmark.y,
                    "z": landmark.z,
                    "visibility": landmark.visibility?.floatValue ?? 1.0
                ]
                landmarksArray.append(landmarkDict)
            }
            
            // Convert world landmarks if available
            if poseIndex < poseLandmarkerResult.worldLandmarks.count {
                let worldLandmarks = poseLandmarkerResult.worldLandmarks[poseIndex]
                for worldLandmark in worldLandmarks {
                    let worldLandmarkDict: [String: Any] = [
                        "x": worldLandmark.x,
                        "y": worldLandmark.y,
                        "z": worldLandmark.z,
                        "visibility": worldLandmark.visibility?.floatValue ?? 1.0
                    ]
                    worldLandmarksArray.append(worldLandmarkDict)
                }
            }
            
            let poseDict: [String: Any] = [
                "landmarks": landmarksArray,
                "worldLandmarks": worldLandmarksArray
            ]
            poses.append(poseDict)
        }
        
        let landmarkData: [String: Any] = [
            "poses": poses,
            "inferenceTime": Int(result.inferenceTime),
            "imageWidth": 640, // Default size, could be extracted from actual image
            "imageHeight": 480,
            "timestamp": Int(Date().timeIntervalSince1970 * 1000)
        ]
        
        DispatchQueue.main.async { [weak self] in
            self?.landmarkEventSink?(landmarkData)
        }
    }
}

// MARK: - Stream Handlers
class LandmarkStreamHandler: NSObject, FlutterStreamHandler {
    private let onListenCallback: (FlutterEventSink?) -> Void
    
    init(onListen: @escaping (FlutterEventSink?) -> Void) {
        self.onListenCallback = onListen
    }
    
    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        onListenCallback(events)
        return nil
    }
    
    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        onListenCallback(nil)
        return nil
    }
}
