import 'dart:async';
import 'dart:developer';

import 'package:flutter/services.dart';

import 'pose_models.dart';

/// Main service for pose detection using MediaPipe
///
/// Provides a simple interface to start camera, stream images and landmarks,
/// and control pose detection functionality.
class PoseDetectionService {
  static const MethodChannel _methodChannel = MethodChannel('ai.buinitylabs.waico/pose_detection');
  static const EventChannel _cameraStreamChannel = EventChannel('ai.buinitylabs.waico/camera_stream');
  static const EventChannel _landmarkStreamChannel = EventChannel('ai.buinitylabs.waico/landmark_stream');

  static PoseDetectionService? _instance;
  static PoseDetectionService get instance => _instance ??= PoseDetectionService._();

  PoseDetectionService._();

  StreamSubscription<dynamic>? _cameraSubscription;
  StreamSubscription<dynamic>? _landmarkSubscription;

  final StreamController<CameraFrame> _cameraController = StreamController<CameraFrame>.broadcast();
  final StreamController<PoseDetectionResult> _landmarkController = StreamController<PoseDetectionResult>.broadcast();
  final StreamController<String> _errorController = StreamController<String>.broadcast();

  bool _isActive = false;

  /// Stream of camera frames (JPEG images)
  Stream<CameraFrame> get cameraStream => _cameraController.stream;

  /// Stream of pose detection results
  Stream<PoseDetectionResult> get landmarkStream => _landmarkController.stream;

  /// Stream of error messages
  Stream<String> get errorStream => _errorController.stream;

  /// Whether pose detection is currently active
  bool get isActive => _isActive;

  /// Start camera and pose detection
  ///
  /// Returns true if started successfully, false otherwise.
  /// Listen to [errorStream] for detailed error information.
  /// Note: Assumes camera permission has already been granted by the caller
  Future<bool> start() async {
    if (_isActive) {
      return true; // Already active
    }

    try {
      // Set up stream listeners
      _setupStreamListeners();

      // Start camera (permission should already be granted by caller)
      await _methodChannel.invokeMethod('startCamera');
      _isActive = true;

      return true;
    } catch (e, s) {
      log('Error starting pose detection', error: e, stackTrace: s);
      _errorController.add('Failed to start pose detection: $e');
      _cleanupStreams();
      return false;
    }
  }

  /// Stop camera and pose detection
  Future<void> stop() async {
    if (!_isActive) {
      return; // Already stopped
    }

    try {
      await _methodChannel.invokeMethod('stopCamera');
    } catch (e, s) {
      log('Error stopping pose detection', error: e, stackTrace: s);
      _errorController.add('Error stopping camera: $e');
    } finally {
      _isActive = false;
      _cleanupStreams();
    }
  }

  /// Switch between front and back camera
  Future<bool> switchCamera() async {
    if (!_isActive) {
      _errorController.add('Cannot switch camera: pose detection not active');
      return false;
    }

    try {
      await _methodChannel.invokeMethod('switchCamera');
      return true;
    } catch (e, s) {
      log('Error switching camera', error: e, stackTrace: s);
      _errorController.add('Failed to switch camera: $e');
      return false;
    }
  }

  /// Set up stream listeners for camera and landmark data
  void _setupStreamListeners() {
    // Listen to camera stream
    _cameraSubscription = _cameraStreamChannel.receiveBroadcastStream().listen(
      (dynamic data) {
        try {
          final frame = CameraFrame.fromMap((data as Map<Object?, Object?>).cast<String, dynamic>());
          _cameraController.add(frame);
        } catch (e, s) {
          log('Error processing camera frame', error: e, stackTrace: s);
          _errorController.add('Error processing camera frame: $e');
        }
      },
      onError: (dynamic error, StackTrace? stackTrace) {
        log('Camera stream error', error: error, stackTrace: stackTrace);
        _errorController.add('Camera stream error: $error');
      },
    );

    // Listen to landmark stream
    _landmarkSubscription = _landmarkStreamChannel.receiveBroadcastStream().listen(
      (dynamic data) {
        try {
          if (data is Map<String, dynamic>) {
            final result = PoseDetectionResult.fromMap(data);
            _landmarkController.add(result);
          }
        } catch (e) {
          _errorController.add('Error processing pose landmarks: $e');
        }
      },
      onError: (dynamic error) {
        _errorController.add('Landmark stream error: $error');
      },
    );
  }

  /// Clean up stream subscriptions
  void _cleanupStreams() {
    _cameraSubscription?.cancel();
    _landmarkSubscription?.cancel();
    _cameraSubscription = null;
    _landmarkSubscription = null;
  }

  /// Dispose of all resources
  void dispose() {
    stop();
    _cameraController.close();
    _landmarkController.close();
    _errorController.close();
    _instance = null;
  }
}

/// Convenience extensions for pose detection results
extension PoseDetectionResultExtensions on PoseDetectionResult {
  /// Get a specific landmark by type
  PoseLandmark? getLandmark(int landmarkType) {
    if (landmarkType < 0 || landmarkType >= landmarks.length) {
      return null;
    }
    return landmarks[landmarkType];
  }

  /// Check if a specific landmark is visible (visibility > 0.5)
  bool isLandmarkVisible(int landmarkType) {
    final landmark = getLandmark(landmarkType);
    return landmark != null && landmark.visibility > 0.5;
  }

  /// Get the center point of the torso (midpoint between shoulders and hips)
  PoseLandmark? get torsoCenter {
    final leftShoulder = getLandmark(PoseLandmarkType.leftShoulder);
    final rightShoulder = getLandmark(PoseLandmarkType.rightShoulder);
    final leftHip = getLandmark(PoseLandmarkType.leftHip);
    final rightHip = getLandmark(PoseLandmarkType.rightHip);

    if (leftShoulder == null || rightShoulder == null || leftHip == null || rightHip == null) {
      return null;
    }

    return PoseLandmark(
      x: (leftShoulder.x + rightShoulder.x + leftHip.x + rightHip.x) / 4,
      y: (leftShoulder.y + rightShoulder.y + leftHip.y + rightHip.y) / 4,
      z: (leftShoulder.z + rightShoulder.z + leftHip.z + rightHip.z) / 4,
      visibility: (leftShoulder.visibility + rightShoulder.visibility + leftHip.visibility + rightHip.visibility) / 4,
    );
  }

  /// Check if the person is facing the camera (based on shoulder orientation)
  bool get isFacingCamera {
    final leftShoulder = getLandmark(PoseLandmarkType.leftShoulder);
    final rightShoulder = getLandmark(PoseLandmarkType.rightShoulder);

    if (leftShoulder == null || rightShoulder == null) {
      return false;
    }

    // If left shoulder appears on the right side of the image, person is facing camera
    return leftShoulder.x > rightShoulder.x;
  }
}
