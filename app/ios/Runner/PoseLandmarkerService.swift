import UIKit
import MediaPipeTasksVision
import AVFoundation

/**
 This protocol must be adopted by any class that wants to get the detection results of the pose landmarker in live stream mode.
 */
protocol PoseLandmarkerServiceLiveStreamDelegate: AnyObject {
  func poseLandmarkerService(_ poseLandmarkerService: PoseLandmarkerService,
                             didFinishDetection result: ResultBundle?,
                             error: Error?)
}

// Initializes and calls the MediaPipe APIs for detection.
class PoseLandmarkerService: NSObject {

  weak var liveStreamDelegate: PoseLandmarkerServiceLiveStreamDelegate?

  var poseLandmarker: PoseLandmarker?
  private(set) var runningMode = RunningMode.liveStream
  private var numPoses: Int
  private var minPoseDetectionConfidence: Float
  private var minPosePresenceConfidence: Float
  private var minTrackingConfidence: Float
  private var modelPath: String

  // MARK: - Custom Initializer
  private init?(modelPath: String?,
                numPoses: Int,
                minPoseDetectionConfidence: Float,
                minPosePresenceConfidence: Float,
                minTrackingConfidence: Float) {
    guard let modelPath = modelPath else { return nil }
    self.modelPath = modelPath
    self.numPoses = numPoses
    self.minPoseDetectionConfidence = minPoseDetectionConfidence
    self.minPosePresenceConfidence = minPosePresenceConfidence
    self.minTrackingConfidence = minTrackingConfidence
    super.init()

    createPoseLandmarker()
  }

  private func createPoseLandmarker() {
    let poseLandmarkerOptions = PoseLandmarkerOptions()
    poseLandmarkerOptions.runningMode = runningMode
    poseLandmarkerOptions.numPoses = numPoses
    poseLandmarkerOptions.minPoseDetectionConfidence = minPoseDetectionConfidence
    poseLandmarkerOptions.minPosePresenceConfidence = minPosePresenceConfidence
    poseLandmarkerOptions.minTrackingConfidence = minTrackingConfidence
    poseLandmarkerOptions.baseOptions.modelAssetPath = modelPath
    
    if runningMode == .liveStream {
      poseLandmarkerOptions.poseLandmarkerLiveStreamDelegate = self
    }
    
    do {
      poseLandmarker = try PoseLandmarker(options: poseLandmarkerOptions)
    }
    catch {
      print("Failed to create pose landmarker: \(error)")
    }
  }

  // MARK: - Static Initializer for Live Stream
  static func liveStreamPoseLandmarkerService(
    modelPath: String?,
    numPoses: Int = 1,
    minPoseDetectionConfidence: Float = 0.5,
    minPosePresenceConfidence: Float = 0.5,
    minTrackingConfidence: Float = 0.5,
    liveStreamDelegate: PoseLandmarkerServiceLiveStreamDelegate?) -> PoseLandmarkerService? {
    let poseLandmarkerService = PoseLandmarkerService(
      modelPath: modelPath,
      numPoses: numPoses,
      minPoseDetectionConfidence: minPoseDetectionConfidence,
      minPosePresenceConfidence: minPosePresenceConfidence,
      minTrackingConfidence: minTrackingConfidence)
    poseLandmarkerService?.liveStreamDelegate = liveStreamDelegate

    return poseLandmarkerService
  }

  // MARK: - Detection Method for Live Stream
  func detectAsync(
    sampleBuffer: CMSampleBuffer,
    orientation: UIImage.Orientation,
    timeStamps: Int) {
    guard let image = try? MPImage(sampleBuffer: sampleBuffer, orientation: orientation) else {
      return
    }
    do {
      try poseLandmarker?.detectAsync(image: image, timestampInMilliseconds: timeStamps)
    } catch {
      print("Pose detection error: \(error)")
    }
  }
  
  /// Cleanup resources
  func close() {
    poseLandmarker = nil
  }
}

// MARK: - PoseLandmarkerLiveStreamDelegate Methods
extension PoseLandmarkerService: PoseLandmarkerLiveStreamDelegate {
    func poseLandmarker(_ poseLandmarker: PoseLandmarker, didFinishDetection result: PoseLandmarkerResult?, timestampInMilliseconds: Int, error: (any Error)?) {
        let resultBundle = ResultBundle(
          inferenceTime: Date().timeIntervalSince1970 * 1000 - Double(timestampInMilliseconds),
          poseLandmarkerResults: [result])
        liveStreamDelegate?.poseLandmarkerService(
          self,
          didFinishDetection: resultBundle,
          error: error)
    }
}

/// A result from the `PoseLandmarkerService`.
struct ResultBundle {
  let inferenceTime: Double
  let poseLandmarkerResults: [PoseLandmarkerResult?]
}
