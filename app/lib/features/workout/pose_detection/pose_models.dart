/// Represents a single pose landmark point in 3D space
class PoseLandmark {
  /// X coordinate (normalized 0-1, relative to image width)
  final double x;

  /// Y coordinate (normalized 0-1, relative to image height)
  final double y;

  /// Z coordinate (depth, relative to hip midpoint)
  final double z;

  /// Visibility confidence (0-1, where 1 is fully visible)
  final double visibility;

  const PoseLandmark({required this.x, required this.y, required this.z, required this.visibility});

  factory PoseLandmark.fromMap(Map<String, dynamic> map) {
    return PoseLandmark(
      x: (map['x'] as num).toDouble(),
      y: (map['y'] as num).toDouble(),
      z: (map['z'] as num).toDouble(),
      visibility: (map['visibility'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {'x': x, 'y': y, 'z': z, 'visibility': visibility};
  }

  @override
  String toString() {
    return 'PoseLandmark(x: $x, y: $y, z: $z, visibility: $visibility)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PoseLandmark && other.x == x && other.y == y && other.z == z && other.visibility == visibility;
  }

  @override
  int get hashCode {
    return x.hashCode ^ y.hashCode ^ z.hashCode ^ visibility.hashCode;
  }
}

/// Represents a complete pose detection result
class PoseDetectionResult {
  /// List of 33 pose landmarks (MediaPipe pose model)
  final List<PoseLandmark> landmarks;

  /// World landmarks (3D coordinates in meters, relative to hip)
  final List<PoseLandmark> worldLandmarks;

  /// Inference time in milliseconds
  final int inferenceTime;

  /// Original image dimensions
  final int imageWidth;
  final int imageHeight;

  /// Timestamp when detection was performed
  final DateTime timestamp;

  const PoseDetectionResult({
    required this.landmarks,
    required this.worldLandmarks,
    required this.inferenceTime,
    required this.imageWidth,
    required this.imageHeight,
    required this.timestamp,
  });

  factory PoseDetectionResult.fromMap(Map<String, dynamic> map) {
    final poses = map['poses'] as List<dynamic>;
    final firstPose = poses.isNotEmpty ? poses.first as Map<String, dynamic> : <String, dynamic>{};

    return PoseDetectionResult(
      landmarks: (firstPose['landmarks'] as List<dynamic>? ?? [])
          .map((landmark) => PoseLandmark.fromMap(landmark as Map<String, dynamic>))
          .toList(),
      worldLandmarks: (firstPose['worldLandmarks'] as List<dynamic>? ?? [])
          .map((landmark) => PoseLandmark.fromMap(landmark as Map<String, dynamic>))
          .toList(),
      inferenceTime: (map['inferenceTime'] as num).toInt(),
      imageWidth: (map['imageWidth'] as num).toInt(),
      imageHeight: (map['imageHeight'] as num).toInt(),
      timestamp: DateTime.fromMillisecondsSinceEpoch((map['timestamp'] as num).toInt()),
    );
  }

  /// Returns true if pose landmarks were detected
  bool get hasPose => landmarks.isNotEmpty;

  /// Returns the number of visible landmarks (visibility > 0.5)
  int get visibleLandmarkCount => landmarks.where((landmark) => landmark.visibility > 0.5).length;

  @override
  String toString() {
    return 'PoseDetectionResult(landmarks: ${landmarks.length}, '
        'worldLandmarks: ${worldLandmarks.length}, '
        'inferenceTime: ${inferenceTime}ms, '
        'visible: $visibleLandmarkCount)';
  }
}

/// Represents a camera frame with image data
class CameraFrame {
  /// JPEG image bytes
  final List<int> imageBytes;

  /// Image dimensions
  final int width;
  final int height;

  /// Timestamp when frame was captured
  final DateTime timestamp;

  const CameraFrame({required this.imageBytes, required this.width, required this.height, required this.timestamp});

  factory CameraFrame.fromMap(Map<String, dynamic> map) {
    return CameraFrame(
      imageBytes: List<int>.from(map['image'] as List<dynamic>),
      width: (map['width'] as num).toInt(),
      height: (map['height'] as num).toInt(),
      timestamp: DateTime.fromMillisecondsSinceEpoch((map['timestamp'] as num).toInt()),
    );
  }

  @override
  String toString() {
    return 'CameraFrame(${width}x$height, ${imageBytes.length} bytes)';
  }
}

/// MediaPipe pose landmark indices for easy access
class PoseLandmarkType {
  static const int nose = 0;
  static const int leftEyeInner = 1;
  static const int leftEye = 2;
  static const int leftEyeOuter = 3;
  static const int rightEyeInner = 4;
  static const int rightEye = 5;
  static const int rightEyeOuter = 6;
  static const int leftEar = 7;
  static const int rightEar = 8;
  static const int mouthLeft = 9;
  static const int mouthRight = 10;
  static const int leftShoulder = 11;
  static const int rightShoulder = 12;
  static const int leftElbow = 13;
  static const int rightElbow = 14;
  static const int leftWrist = 15;
  static const int rightWrist = 16;
  static const int leftPinky = 17;
  static const int rightPinky = 18;
  static const int leftIndex = 19;
  static const int rightIndex = 20;
  static const int leftThumb = 21;
  static const int rightThumb = 22;
  static const int leftHip = 23;
  static const int rightHip = 24;
  static const int leftKnee = 25;
  static const int rightKnee = 26;
  static const int leftAnkle = 27;
  static const int rightAnkle = 28;
  static const int leftHeel = 29;
  static const int rightHeel = 30;
  static const int leftFootIndex = 31;
  static const int rightFootIndex = 32;

  /// Returns the name of the landmark for the given index
  static String getName(int index) {
    const names = [
      'nose',
      'left_eye_inner',
      'left_eye',
      'left_eye_outer',
      'right_eye_inner',
      'right_eye',
      'right_eye_outer',
      'left_ear',
      'right_ear',
      'mouth_left',
      'mouth_right',
      'left_shoulder',
      'right_shoulder',
      'left_elbow',
      'right_elbow',
      'left_wrist',
      'right_wrist',
      'left_pinky',
      'right_pinky',
      'left_index',
      'right_index',
      'left_thumb',
      'right_thumb',
      'left_hip',
      'right_hip',
      'left_knee',
      'right_knee',
      'left_ankle',
      'right_ankle',
      'left_heel',
      'right_heel',
      'left_foot_index',
      'right_foot_index',
    ];
    return index < names.length ? names[index] : 'unknown';
  }
}
