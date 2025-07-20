import UIKit
import AVFoundation

protocol CameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer, orientation: UIImage.Orientation)
    func cameraManager(_ manager: CameraManager, didFailWithError error: Error)
}

class CameraManager: NSObject {
    weak var delegate: CameraManagerDelegate?
    
    private let session = AVCaptureSession()
    private var videoDataOutput = AVCaptureVideoDataOutput()
    private let videoDataOutputQueue = DispatchQueue(label: "VideoDataOutput", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    private var frontCamera: AVCaptureDevice?
    private var backCamera: AVCaptureDevice?
    private var currentCameraPosition: AVCaptureDevice.Position = .back
    private var videoDeviceInput: AVCaptureDeviceInput?
    
    private var isSessionRunning = false
    
    override init() {
        super.init()
        setupCaptureSession()
    }
    
    // MARK: - Setup
    private func setupCaptureSession() {
        session.beginConfiguration()
        
        // Set session preset for optimization
        if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        }
        
        // Setup cameras
        setupCameras()
        
        // Setup camera input
        guard let backCamera = backCamera,
              let videoDeviceInput = try? AVCaptureDeviceInput(device: backCamera),
              session.canAddInput(videoDeviceInput) else {
            print("Could not create video device input for back camera")
            session.commitConfiguration()
            return
        }
        
        session.addInput(videoDeviceInput)
        self.videoDeviceInput = videoDeviceInput
        
        // Setup video output
        setupVideoOutput()
        
        session.commitConfiguration()
    }
    
    private func setupCameras() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        )
        
        for device in discoverySession.devices {
            switch device.position {
            case .front:
                frontCamera = device
            case .back:
                backCamera = device
            default:
                break
            }
        }
    }
    
    private func setupVideoOutput() {
        videoDataOutput.videoSettings = [
            (kCVPixelBufferPixelFormatTypeKey as String): NSNumber(value: kCVPixelFormatType_32BGRA)
        ]
        
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: videoDataOutputQueue)
        
        guard session.canAddOutput(videoDataOutput) else {
            print("Could not add video data output to the session")
            return
        }
        
        session.addOutput(videoDataOutput)
        
        // Configure video orientation
        if let connection = videoDataOutput.connection(with: .video) {
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }
    }
    
    // MARK: - Public Methods
    func checkCameraPermission() -> Bool {
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }
    
    func requestCameraPermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
    
    func startSession() {
        guard !isSessionRunning else { return }
        
        videoDataOutputQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.startRunning()
            self.isSessionRunning = self.session.isRunning
        }
    }
    
    func stopSession() {
        guard isSessionRunning else { return }
        
        videoDataOutputQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.stopRunning()
            self.isSessionRunning = self.session.isRunning
        }
    }
    
    func switchCamera() {
        guard let currentVideoDeviceInput = videoDeviceInput else { return }
        
        session.beginConfiguration()
        session.removeInput(currentVideoDeviceInput)
        
        let newCameraPosition: AVCaptureDevice.Position = currentCameraPosition == .back ? .front : .back
        let newCamera = newCameraPosition == .back ? backCamera : frontCamera
        
        guard let newCamera = newCamera,
              let newVideoDeviceInput = try? AVCaptureDeviceInput(device: newCamera),
              session.canAddInput(newVideoDeviceInput) else {
            // Revert to original camera if switching fails
            session.addInput(currentVideoDeviceInput)
            session.commitConfiguration()
            return
        }
        
        session.addInput(newVideoDeviceInput)
        videoDeviceInput = newVideoDeviceInput
        currentCameraPosition = newCameraPosition
        
        session.commitConfiguration()
    }
    
    var isRunning: Bool {
        return isSessionRunning
    }
    
    var isFrontCamera: Bool {
        return currentCameraPosition == .front
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        // Determine orientation based on camera position
        let orientation: UIImage.Orientation = currentCameraPosition == .front ? .leftMirrored : .right
        
        delegate?.cameraManager(self, didOutput: sampleBuffer, orientation: orientation)
    }
    
    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Handle dropped frames if needed
        print("Dropped camera frame")
    }
}
