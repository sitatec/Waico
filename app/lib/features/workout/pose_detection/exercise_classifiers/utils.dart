import 'dart:math';

import 'package:vector_math/vector_math_64.dart';
import 'package:waico/features/workout/pose_detection/pose_models.dart';

/// A utility class providing static methods for pose analysis.
class PoseUtilities {
  /// Calculates the 3D angle between three landmarks using vector_math.
  static double getAngle(PoseLandmark firstPoint, PoseLandmark midPoint, PoseLandmark lastPoint) {
    final p1 = Vector3(firstPoint.x, firstPoint.y, firstPoint.z);
    final p2 = Vector3(midPoint.x, midPoint.y, midPoint.z);
    final p3 = Vector3(lastPoint.x, lastPoint.y, lastPoint.z);

    final v1 = p1 - p2
      ..normalize();
    final v2 = p3 - p2
      ..normalize();

    final dotProduct = v1.dot(v2).clamp(-1.0, 1.0);
    final angleRad = acos(dotProduct);
    return angleRad * 180.0 / pi;
  }

  /// Calculates the midpoint between two landmarks.
  static PoseLandmark getMidpoint(PoseLandmark p1, PoseLandmark p2) {
    return PoseLandmark(
      x: (p1.x + p2.x) / 2,
      y: (p1.y + p2.y) / 2,
      z: (p1.z + p2.z) / 2,
      visibility: min(p1.visibility, p2.visibility),
    );
  }

  /// Gets the vertical distance between two landmarks using image coordinates.
  static double getVerticalDistance(PoseLandmark p1, PoseLandmark p2) {
    return (p1.y - p2.y).abs();
  }

  /// Normalizes a value from a given range to a 0-1 scale.
  static double normalize(double value, double minVal, double maxVal) {
    if (maxVal == minVal) return 0.0;
    return ((value - minVal) / (maxVal - minVal)).clamp(0.0, 1.0);
  }

  /// Determines which side of the body is more visible to the camera.
  static bool isLeftBodyVisible(List<PoseLandmark> landmarks) {
    final leftVisibility =
        landmarks[PoseLandmarkType.leftShoulder].visibility +
        landmarks[PoseLandmarkType.leftHip].visibility +
        landmarks[PoseLandmarkType.leftKnee].visibility +
        landmarks[PoseLandmarkType.leftAnkle].visibility;
    final rightVisibility =
        landmarks[PoseLandmarkType.rightShoulder].visibility +
        landmarks[PoseLandmarkType.rightHip].visibility +
        landmarks[PoseLandmarkType.rightKnee].visibility +
        landmarks[PoseLandmarkType.rightAnkle].visibility;
    return leftVisibility >= rightVisibility;
  }
}
