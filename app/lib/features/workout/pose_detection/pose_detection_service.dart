import 'dart:async';
import 'dart:developer';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'pose_models.dart';

/// Service for pose detection using MediaPipe through platform channels
///
/// This service only handles pose detection data, not camera streaming.
/// Camera rendering is handled by native platform views.
class PoseDetectionService {
  static const MethodChannel _methodChannel = MethodChannel('ai.buinitylabs.waico/pose_detection');
  static const EventChannel _landmarkStreamChannel = EventChannel('ai.buinitylabs.waico/landmark_stream');

  static PoseDetectionService? _instance;
  static PoseDetectionService get instance => _instance ??= PoseDetectionService._();

  PoseDetectionService._();

  StreamSubscription<dynamic>? _landmarkSubscription;

  final StreamController<PoseDetectionResult> _landmarkController = StreamController<PoseDetectionResult>.broadcast();
  final StreamController<String> _errorController = StreamController<String>.broadcast();

  bool _isActive = false;

  /// Stream of pose detection results
  Stream<PoseDetectionResult> get landmarkStream => _landmarkController.stream;

  /// Stream of error messages
  Stream<String> get errorStream => _errorController.stream;

  /// Whether pose detection is currently active
  bool get isActive => _isActive;

  Future<bool> get hasCameraPermission => Permission.camera.request().isGranted;

  /// Start pose detection
  ///
  /// Returns true if started successfully, false otherwise.
  /// Listen to [errorStream] for detailed error information.
  /// Note: This only starts pose detection, camera is handled by native views
  Future<bool> start() async {
    if (_isActive) {
      log('Pose detection already active');
      return true; // Already active
    }

    try {
      log('Starting pose detection service...');

      // Set up stream listeners first
      _setupStreamListeners();

      // Start pose detection service
      await _methodChannel.invokeMethod('startCamera');
      _isActive = true;

      log('Pose detection service started successfully');
      return true;
    } catch (e, s) {
      log('Error starting pose detection', error: e, stackTrace: s);
      _errorController.add('Failed to start pose detection: $e');
      _cleanupStreams();
      return false;
    }
  }

  /// Stop pose detection
  Future<void> stop() async {
    if (!_isActive) {
      log('Pose detection already stopped');
      return; // Already stopped
    }

    log('Stopping pose detection service...');

    try {
      await _methodChannel.invokeMethod('stopCamera');
      log('Pose detection service stopped successfully');
    } catch (e, s) {
      log('Error stopping pose detection', error: e, stackTrace: s);
      _errorController.add('Error stopping pose detection: $e');
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

  /// Set up stream listeners for pose detection data
  void _setupStreamListeners() {
    // Listen to landmark stream only (camera handled by native view)
    _landmarkSubscription = _landmarkStreamChannel.receiveBroadcastStream().listen(
      (dynamic data) {
        try {
          final result = PoseDetectionResult.fromMap(_deepCast(data));
          _landmarkController.add(result);
        } catch (e, s) {
          log('Error parsing pose landmarks', error: e, stackTrace: s);
          _errorController.add('Error processing pose landmarks $e');
        }
      },
      onError: (dynamic error) {
        _errorController.add('Landmark stream error: $error');
      },
    );
  }

  dynamic _deepCast(dynamic value) {
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), _deepCast(val)));
    } else if (value is List) {
      return value.map(_deepCast).toList();
    } else {
      return value; // int, double, bool, String, null, etc.
    }
  }

  /// Clean up stream subscriptions
  void _cleanupStreams() {
    _landmarkSubscription?.cancel();
    _landmarkSubscription = null;
  }

  /// Dispose of all resources
  Future<void> dispose() async {
    log('Disposing pose detection service');

    // Call native dispose method to clean up resources
    try {
      await _methodChannel.invokeMethod('dispose');
    } catch (e) {
      log('Error calling native dispose method', error: e);
    }

    // Clean up Flutter resources
    await stop();
    await _landmarkController.close();
    await _errorController.close();
    _instance = null;

    log('Pose detection service disposed');
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
