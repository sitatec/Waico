import 'dart:collection';
import 'dart:math';
import 'package:vector_math/vector_math_64.dart';
import 'package:waico/features/workout/pose_detection/pose_models.dart';

// ============================================================================
// 1. CORE UTILITIES
// ============================================================================

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
        landmarks[PoseLandmarkType.leftKnee].visibility;
    final rightVisibility =
        landmarks[PoseLandmarkType.rightShoulder].visibility +
        landmarks[PoseLandmarkType.rightHip].visibility +
        landmarks[PoseLandmarkType.rightKnee].visibility;
    return leftVisibility >= rightVisibility;
  }
}

// ============================================================================
// 2. BASE CLASSIFIER
// ============================================================================

/// An abstract base class for all exercise classifiers.
abstract class PoseClassifier {
  final int smoothingWindow;
  final Queue<Map<String, double>> _history = Queue();

  PoseClassifier({this.smoothingWindow = 5});

  Map<String, double> classify({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    final rawProbabilities = _calculateProbabilities(worldLandmarks: worldLandmarks, imageLandmarks: imageLandmarks);
    _history.add(rawProbabilities);
    if (_history.length > smoothingWindow) {
      _history.removeFirst();
    }
    return _getSmoothedProbabilities();
  }

  Map<String, double> _calculateProbabilities({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  });

  /// Calculate exercise-specific form metrics
  /// Returns a map of metric names to scores (0.0 - 1.0)
  Map<String, double> calculateFormMetrics({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    // Default implementation returns overall visibility
    final visibilityScore = worldLandmarks.map((l) => l.visibility).reduce((a, b) => a + b) / worldLandmarks.length;
    return {'overall_visibility': visibilityScore};
  }

  Map<String, double> _getSmoothedProbabilities() {
    if (_history.isEmpty) return {'up': 0.5, 'down': 0.5};
    double upSum = 0.0;
    double downSum = 0.0;
    for (final probs in _history) {
      upSum += probs['up'] ?? 0.0;
      downSum += probs['down'] ?? 0.0;
    }
    return {'up': upSum / _history.length, 'down': downSum / _history.length};
  }

  Map<String, double> _neutralResult() => {'up': 0.5, 'down': 0.5};
}

// ============================================================================
// 3. ENHANCED EXERCISE CLASSIFIERS
// ============================================================================

// -------------------- PUSH-UP FAMILY --------------------

enum PushUpType { standard, knee, wall, incline, decline, diamond, wide }

class PushUpClassifier extends PoseClassifier {
  final PushUpType type;

  PushUpClassifier({this.type = PushUpType.standard, int smoothingWindow = 5})
    : super(smoothingWindow: smoothingWindow);

  @override
  Map<String, double> _calculateProbabilities({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    final isLeftVisible = PoseUtilities.isLeftBodyVisible(worldLandmarks);
    final shoulderIdx = isLeftVisible ? PoseLandmarkType.leftShoulder : PoseLandmarkType.rightShoulder;
    final elbowIdx = isLeftVisible ? PoseLandmarkType.leftElbow : PoseLandmarkType.rightElbow;
    final wristIdx = isLeftVisible ? PoseLandmarkType.leftWrist : PoseLandmarkType.rightWrist;
    final hipIdx = isLeftVisible ? PoseLandmarkType.leftHip : PoseLandmarkType.rightHip;

    // Use a mix of world and image landmarks for robustness.
    final shoulder3D = worldLandmarks[shoulderIdx];
    final elbow3D = worldLandmarks[elbowIdx];
    final wrist3D = worldLandmarks[wristIdx];

    final shoulder2D = imageLandmarks[shoulderIdx];
    final wrist2D = imageLandmarks[wristIdx];
    final hip2D = imageLandmarks[hipIdx];

    if (shoulder3D.visibility < 0.7 || elbow3D.visibility < 0.7 || wrist3D.visibility < 0.7) {
      return _neutralResult();
    }

    // Get variation-specific angle thresholds
    final angleThresholds = _getAngleThresholds();
    final heightRanges = _getHeightRanges();

    // Signal 1: Elbow Angle (Primary, heavily weighted)
    final elbowAngle = PoseUtilities.getAngle(shoulder3D, elbow3D, wrist3D);

    // Use variation-specific thresholds for better discrimination
    double angleProb;
    if (elbowAngle >= angleThresholds['upMin']!) {
      // Clearly in UP range
      angleProb = 1.0;
    } else if (elbowAngle <= angleThresholds['downMax']!) {
      // Clearly in DOWN range
      angleProb = 0.0;
    } else {
      // Overlap region - use linear interpolation but be conservative
      final range = angleThresholds['upMin']! - angleThresholds['downMax']!;
      angleProb = (elbowAngle - angleThresholds['downMax']!) / range;
      // Apply sigmoid-like function to make the transition less linear
      angleProb = angleProb * angleProb; // Square to push toward extremes
    }

    // Signal 2: Shoulder Height relative to Wrist (Secondary, variation-adjusted)
    final shoulderHeight = PoseUtilities.getVerticalDistance(shoulder2D, wrist2D);
    final torsoHeight = PoseUtilities.getVerticalDistance(shoulder2D, hip2D);

    if (torsoHeight < 0.01) return _neutralResult();

    final normalizedShoulderHeight = shoulderHeight / torsoHeight;
    // Invert the height signal: higher height = more likely DOWN position
    final heightProb =
        1.0 - PoseUtilities.normalize(normalizedShoulderHeight, heightRanges['min']!, heightRanges['max']!);

    // Weight angle much more heavily since it's more reliable
    final upProbability = (angleProb * 0.9 + heightProb * 0.1);
    return {'up': upProbability, 'down': 1.0 - upProbability};
  }

  /// Returns variation-specific angle thresholds for elbow angle classification
  Map<String, double> _getAngleThresholds() {
    switch (type) {
      case PushUpType.standard:
        return {'upMin': 150.0, 'downMax': 120.0}; // Standard range of motion
      case PushUpType.knee:
        return {'upMin': 150.0, 'downMax': 120.0}; // Based on provided knee push-up data
      case PushUpType.wall:
        return {'upMin': 140.0, 'downMax': 130.0}; // Smaller range for wall push-ups
      case PushUpType.incline:
        return {'upMin': 155.0, 'downMax': 125.0}; // Slightly larger range due to angle
      case PushUpType.decline:
        return {'upMin': 145.0, 'downMax': 115.0}; // Slightly smaller range due to angle
      case PushUpType.diamond:
        return {'upMin': 145.0, 'downMax': 115.0}; // Narrower hand position affects elbow
      case PushUpType.wide:
        return {'upMin': 155.0, 'downMax': 125.0}; // Wider hand position affects elbow
    }
  }

  /// Returns variation-specific height normalization ranges
  Map<String, double> _getHeightRanges() {
    switch (type) {
      case PushUpType.standard:
        return {'min': 1.5, 'max': 6.0}; // Standard torso-relative ranges
      case PushUpType.knee:
        return {'min': 1.5, 'max': 6.0}; // Based on provided knee push-up data
      case PushUpType.wall:
        return {'min': 0.5, 'max': 3.0}; // Much smaller height variation
      case PushUpType.incline:
        return {'min': 1.0, 'max': 4.5}; // Reduced range due to incline
      case PushUpType.decline:
        return {'min': 2.0, 'max': 7.5}; // Increased range due to decline
      case PushUpType.diamond:
        return {'min': 1.5, 'max': 6.0}; // Similar to standard
      case PushUpType.wide:
        return {'min': 1.5, 'max': 6.0}; // Similar to standard
    }
  }

  @override
  Map<String, double> calculateFormMetrics({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    final metrics = <String, double>{};

    try {
      final leftShoulder = worldLandmarks[PoseLandmarkType.leftShoulder];
      final rightShoulder = worldLandmarks[PoseLandmarkType.rightShoulder];
      final leftHip = worldLandmarks[PoseLandmarkType.leftHip];
      final rightHip = worldLandmarks[PoseLandmarkType.rightHip];

      // Body alignment (straight line from shoulders to contact points)
      final shoulderMid = PoseUtilities.getMidpoint(leftShoulder, rightShoulder);
      final hipMid = PoseUtilities.getMidpoint(leftHip, rightHip);

      // Different alignment calculations based on push-up type
      switch (type) {
        case PushUpType.knee:
          final leftKnee = worldLandmarks[PoseLandmarkType.leftKnee];
          final rightKnee = worldLandmarks[PoseLandmarkType.rightKnee];
          final kneeMid = PoseUtilities.getMidpoint(leftKnee, rightKnee);
          // Use knee mid instead of ankle mid for knee push-ups
          final bodyAngle = PoseUtilities.getAngle(shoulderMid, hipMid, kneeMid);
          // For knee push-ups, ideal angle is around 150-160 degrees (slight bend is acceptable)
          final targetAngle = 155.0;
          final alignmentScore = 1.0 - (targetAngle - bodyAngle).abs() / 45.0; // Normalize to 0-1
          metrics['body_alignment'] = alignmentScore.clamp(0.0, 1.0);
          break;
        case PushUpType.wall:
          // For wall push-ups, body should be at an angle to the wall
          // Check torso angle relative to vertical
          final leftAnkle = worldLandmarks[PoseLandmarkType.leftAnkle];
          final rightAnkle = worldLandmarks[PoseLandmarkType.rightAnkle];
          final ankleMid = PoseUtilities.getMidpoint(leftAnkle, rightAnkle);
          final bodyAngle = PoseUtilities.getAngle(shoulderMid, hipMid, ankleMid);
          // For wall push-ups, ideal is around 160-170 degrees (body at angle)
          final targetAngle = 165.0;
          final alignmentScore = 1.0 - (targetAngle - bodyAngle).abs() / 30.0;
          metrics['body_alignment'] = alignmentScore.clamp(0.0, 1.0);
          break;
        case PushUpType.incline:
        case PushUpType.decline:
          // For incline/decline, check body straightness with adjusted expectations
          final leftAnkle = worldLandmarks[PoseLandmarkType.leftAnkle];
          final rightAnkle = worldLandmarks[PoseLandmarkType.rightAnkle];
          final ankleMid = PoseUtilities.getMidpoint(leftAnkle, rightAnkle);
          final bodyAngle = PoseUtilities.getAngle(shoulderMid, hipMid, ankleMid);
          // Slightly more lenient for incline/decline variations
          final alignmentScore = 1.0 - (175.0 - bodyAngle).abs() / 50.0;
          metrics['body_alignment'] = alignmentScore.clamp(0.0, 1.0);
          break;
        default:
          // Standard, diamond, wide push-ups - straight body line
          final leftAnkle = worldLandmarks[PoseLandmarkType.leftAnkle];
          final rightAnkle = worldLandmarks[PoseLandmarkType.rightAnkle];
          final ankleMid = PoseUtilities.getMidpoint(leftAnkle, rightAnkle);
          final bodyAngle = PoseUtilities.getAngle(shoulderMid, hipMid, ankleMid);
          final alignmentScore = 1.0 - (180.0 - bodyAngle).abs() / 45.0;
          metrics['body_alignment'] = alignmentScore.clamp(0.0, 1.0);
      }

      // Hand width evaluation (variation-specific)
      final leftWrist = imageLandmarks[PoseLandmarkType.leftWrist];
      final rightWrist = imageLandmarks[PoseLandmarkType.rightWrist];
      final leftShoulderImg = imageLandmarks[PoseLandmarkType.leftShoulder];
      final rightShoulderImg = imageLandmarks[PoseLandmarkType.rightShoulder];

      final handWidth = (leftWrist.x - rightWrist.x).abs();
      final shoulderWidth = (leftShoulderImg.x - rightShoulderImg.x).abs();
      final widthRatio = shoulderWidth > 0 ? handWidth / shoulderWidth : 0.0;

      double widthScore;
      switch (type) {
        case PushUpType.diamond:
          // Diamond push-ups: hands should be close together (ratio < 0.5)
          final idealRatio = 0.3;
          widthScore = 1.0 - (widthRatio - idealRatio).abs().clamp(0.0, 1.0);
          break;
        case PushUpType.wide:
          // Wide push-ups: hands should be wider than shoulders (ratio > 1.5)
          final idealRatio = 1.8;
          widthScore = 1.0 - (widthRatio - idealRatio).abs().clamp(0.0, 1.0);
          break;
        default:
          // Standard, knee, wall, incline, decline: hands slightly wider than shoulders
          final idealRatio = 1.25;
          widthScore = 1.0 - (widthRatio - idealRatio).abs().clamp(0.0, 1.0);
      }
      metrics['hand_width'] = widthScore;

      // Wrist positioning (should be roughly under shoulders for most variations)
      final wristShoulderDistance = sqrt(
        pow(leftWrist.x - leftShoulderImg.x, 2) + pow(rightWrist.x - rightShoulderImg.x, 2),
      );
      final wristScore = 1.0 - (wristShoulderDistance * 2).clamp(0.0, 1.0);
      metrics['wrist_positioning'] = wristScore;
    } catch (e) {
      // Fallback values on error
      metrics['body_alignment'] = 0.5;
      metrics['wrist_positioning'] = 0.5;
      metrics['hand_width'] = 0.5;
    }

    // Add overall visibility
    final visibilityScore = worldLandmarks.map((l) => l.visibility).reduce((a, b) => a + b) / worldLandmarks.length;
    metrics['overall_visibility'] = visibilityScore;

    return metrics;
  }
}

// -------------------- SQUAT FAMILY --------------------

class SquatClassifier extends PoseClassifier {
  @override
  Map<String, double> _calculateProbabilities({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    final isLeftVisible = PoseUtilities.isLeftBodyVisible(worldLandmarks);
    final hipIdx = isLeftVisible ? PoseLandmarkType.leftHip : PoseLandmarkType.rightHip;
    final kneeIdx = isLeftVisible ? PoseLandmarkType.leftKnee : PoseLandmarkType.rightKnee;
    final ankleIdx = isLeftVisible ? PoseLandmarkType.leftAnkle : PoseLandmarkType.rightAnkle;

    final hip3D = worldLandmarks[hipIdx];
    final knee3D = worldLandmarks[kneeIdx];
    final ankle3D = worldLandmarks[ankleIdx];

    final hip2D = imageLandmarks[hipIdx];
    final knee2D = imageLandmarks[kneeIdx];

    if (hip3D.visibility < 0.8 || knee3D.visibility < 0.8 || ankle3D.visibility < 0.8) {
      return _neutralResult();
    }

    // --- Granular Algorithm ---
    // 1. Knee Angle (Primary): Angle of the knee joint.
    // 2. Hip Height (Secondary): Vertical position of the hip relative to the knee.

    // Signal 1: Knee Angle
    final kneeAngle = PoseUtilities.getAngle(hip3D, knee3D, ankle3D);
    final angleProb = PoseUtilities.normalize(kneeAngle, 90.0, 175.0);

    // Signal 2: Hip Height over Knee
    // In a deep squat, hips are at or below knee level.
    final hipKneeHeightDiff = knee2D.y - hip2D.y; // Positive when hip is above knee
    final shinHeight = PoseUtilities.getVerticalDistance(knee2D, imageLandmarks[ankleIdx]);
    if (shinHeight < 0.01) return _neutralResult();

    final normalizedHipHeight = hipKneeHeightDiff / shinHeight;
    // Down: hip is near/below knee (ratio ~0). Up: hip is high above knee (ratio ~1.0-1.2).
    final heightProb = PoseUtilities.normalize(normalizedHipHeight, 0.0, 1.2);

    // Combine probabilities
    final upProbability = (angleProb * 0.6 + heightProb * 0.4);
    return {'up': upProbability, 'down': 1.0 - upProbability};
  }

  @override
  Map<String, double> calculateFormMetrics({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    final metrics = <String, double>{};

    try {
      final leftKnee = worldLandmarks[PoseLandmarkType.leftKnee];
      final rightKnee = worldLandmarks[PoseLandmarkType.rightKnee];
      final leftAnkle = worldLandmarks[PoseLandmarkType.leftAnkle];
      final rightAnkle = worldLandmarks[PoseLandmarkType.rightAnkle];
      final leftHip = worldLandmarks[PoseLandmarkType.leftHip];
      final rightHip = worldLandmarks[PoseLandmarkType.rightHip];

      // Knee tracking (knees should track over toes)
      final kneeAnkleDistance = sqrt(pow(leftKnee.x - leftAnkle.x, 2) + pow(rightKnee.x - rightAnkle.x, 2));
      final kneeTrackingScore = 1.0 - (kneeAnkleDistance * 10).clamp(0.0, 1.0);
      metrics['knee_tracking'] = kneeTrackingScore;

      // Hip symmetry (both hips should be at similar height)
      final hipHeightDiff = (leftHip.y - rightHip.y).abs();
      final hipSymmetryScore = 1.0 - (hipHeightDiff * 20).clamp(0.0, 1.0);
      metrics['hip_symmetry'] = hipSymmetryScore;

      // Depth (hip should go below knee level in a proper squat)
      final hipKneeDiff = (leftHip.y + rightHip.y) / 2 - (leftKnee.y + rightKnee.y) / 2;
      final depthScore = hipKneeDiff > 0 ? 1.0 : 0.5;
      metrics['squat_depth'] = depthScore;

      // Stance width (feet should be shoulder-width apart)
      final footWidth = (leftAnkle.x - rightAnkle.x).abs();
      final shoulderWidth =
          (worldLandmarks[PoseLandmarkType.leftShoulder].x - worldLandmarks[PoseLandmarkType.rightShoulder].x).abs();
      final stanceRatio = shoulderWidth > 0 ? footWidth / shoulderWidth : 0.0;
      final stanceScore = 1.0 - (stanceRatio - 1.1).abs().clamp(0.0, 1.0);
      metrics['stance_width'] = stanceScore;
    } catch (e) {
      // Fallback values on error
      metrics['knee_tracking'] = 0.5;
      metrics['hip_symmetry'] = 0.5;
      metrics['squat_depth'] = 0.5;
      metrics['stance_width'] = 0.5;
    }

    // Add overall visibility
    final visibilityScore = worldLandmarks.map((l) => l.visibility).reduce((a, b) => a + b) / worldLandmarks.length;
    metrics['overall_visibility'] = visibilityScore;

    return metrics;
  }
}

class SumoSquatClassifier extends PoseClassifier {
  // Sumo Squat logic is similar to a regular squat but averages both legs.
  @override
  Map<String, double> _calculateProbabilities({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    // We average both legs as user is facing the camera.
    final lHip = worldLandmarks[PoseLandmarkType.leftHip];
    final lKnee = worldLandmarks[PoseLandmarkType.leftKnee];
    final lAnkle = worldLandmarks[PoseLandmarkType.leftAnkle];
    final rHip = worldLandmarks[PoseLandmarkType.rightHip];
    final rKnee = worldLandmarks[PoseLandmarkType.rightKnee];
    final rAnkle = worldLandmarks[PoseLandmarkType.rightAnkle];

    if (lKnee.visibility < 0.7 || rKnee.visibility < 0.7) return _neutralResult();

    // Calculate angles for both legs
    final lKneeAngle = PoseUtilities.getAngle(lHip, lKnee, lAnkle);
    final rKneeAngle = PoseUtilities.getAngle(rHip, rKnee, rAnkle);
    final avgKneeAngle = (lKneeAngle + rKneeAngle) / 2;

    final angleProb = PoseUtilities.normalize(avgKneeAngle, 90.0, 175.0);

    // Hip height relative to knees
    final lHip2D = imageLandmarks[PoseLandmarkType.leftHip];
    final rHip2D = imageLandmarks[PoseLandmarkType.rightHip];
    final lKnee2D = imageLandmarks[PoseLandmarkType.leftKnee];
    final rKnee2D = imageLandmarks[PoseLandmarkType.rightKnee];

    final avgHipHeight = (lHip2D.y + rHip2D.y) / 2;
    final avgKneeHeight = (lKnee2D.y + rKnee2D.y) / 2;
    final hipKneeHeightDiff = avgKneeHeight - avgHipHeight;

    final shinHeight = PoseUtilities.getVerticalDistance(lKnee2D, imageLandmarks[PoseLandmarkType.leftAnkle]);
    if (shinHeight < 0.01) return _neutralResult();

    final normalizedHipHeight = hipKneeHeightDiff / shinHeight;
    final heightProb = PoseUtilities.normalize(normalizedHipHeight, 0.0, 1.2);

    final upProbability = (angleProb * 0.6 + heightProb * 0.4);
    return {'up': upProbability, 'down': 1.0 - upProbability};
  }

  @override
  Map<String, double> calculateFormMetrics({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    final metrics = <String, double>{};

    try {
      final leftKnee = worldLandmarks[PoseLandmarkType.leftKnee];
      final rightKnee = worldLandmarks[PoseLandmarkType.rightKnee];
      final leftAnkle = worldLandmarks[PoseLandmarkType.leftAnkle];
      final rightAnkle = worldLandmarks[PoseLandmarkType.rightAnkle];
      final leftHip = worldLandmarks[PoseLandmarkType.leftHip];
      final rightHip = worldLandmarks[PoseLandmarkType.rightHip];

      // Knee tracking (both knees should track over toes)
      final leftKneeAnkleDistance = sqrt(pow(leftKnee.x - leftAnkle.x, 2));
      final rightKneeAnkleDistance = sqrt(pow(rightKnee.x - rightAnkle.x, 2));
      final avgKneeTrackingScore = 1.0 - ((leftKneeAnkleDistance + rightKneeAnkleDistance) / 2 * 10).clamp(0.0, 1.0);
      metrics['knee_tracking'] = avgKneeTrackingScore;

      // Hip symmetry
      final hipHeightDiff = (leftHip.y - rightHip.y).abs();
      final hipSymmetryScore = 1.0 - (hipHeightDiff * 20).clamp(0.0, 1.0);
      metrics['hip_symmetry'] = hipSymmetryScore;

      // Stance width (should be wider than regular squat)
      final footWidth = (leftAnkle.x - rightAnkle.x).abs();
      final shoulderWidth =
          (worldLandmarks[PoseLandmarkType.leftShoulder].x - worldLandmarks[PoseLandmarkType.rightShoulder].x).abs();
      final stanceRatio = shoulderWidth > 0 ? footWidth / shoulderWidth : 0.0;
      // Sumo squats should have wider stance (1.3-1.8)
      final stanceScore = 1.0 - (stanceRatio - 1.55).abs().clamp(0.0, 1.0);
      metrics['sumo_stance_width'] = stanceScore;

      // Depth
      final hipKneeDiff = (leftHip.y + rightHip.y) / 2 - (leftKnee.y + rightKnee.y) / 2;
      final depthScore = hipKneeDiff > 0 ? 1.0 : 0.5;
      metrics['squat_depth'] = depthScore;
    } catch (e) {
      metrics['knee_tracking'] = 0.5;
      metrics['hip_symmetry'] = 0.5;
      metrics['sumo_stance_width'] = 0.5;
      metrics['squat_depth'] = 0.5;
    }

    final visibilityScore = worldLandmarks.map((l) => l.visibility).reduce((a, b) => a + b) / worldLandmarks.length;
    metrics['overall_visibility'] = visibilityScore;

    return metrics;
  }
}

enum SplitSquatSide { left, right }

class SplitSquatClassifier extends PoseClassifier {
  final SplitSquatSide frontLeg;

  SplitSquatClassifier({required this.frontLeg});

  @override
  Map<String, double> _calculateProbabilities({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    // Focus on front leg for split squat analysis
    final frontHipIdx = frontLeg == SplitSquatSide.left ? PoseLandmarkType.leftHip : PoseLandmarkType.rightHip;
    final frontKneeIdx = frontLeg == SplitSquatSide.left ? PoseLandmarkType.leftKnee : PoseLandmarkType.rightKnee;
    final frontAnkleIdx = frontLeg == SplitSquatSide.left ? PoseLandmarkType.leftAnkle : PoseLandmarkType.rightAnkle;

    final frontHip = worldLandmarks[frontHipIdx];
    final frontKnee = worldLandmarks[frontKneeIdx];
    final frontAnkle = worldLandmarks[frontAnkleIdx];

    if (frontHip.visibility < 0.8 || frontKnee.visibility < 0.8 || frontAnkle.visibility < 0.8) {
      return _neutralResult();
    }

    // Front leg knee angle
    final kneeAngle = PoseUtilities.getAngle(frontHip, frontKnee, frontAnkle);
    final angleProb = PoseUtilities.normalize(kneeAngle, 90.0, 175.0);

    // Hip height relative to front knee
    final frontHip2D = imageLandmarks[frontHipIdx];
    final frontKnee2D = imageLandmarks[frontKneeIdx];
    final hipKneeHeightDiff = frontKnee2D.y - frontHip2D.y;
    final shinHeight = PoseUtilities.getVerticalDistance(frontKnee2D, imageLandmarks[frontAnkleIdx]);

    if (shinHeight < 0.01) return _neutralResult();

    final normalizedHipHeight = hipKneeHeightDiff / shinHeight;
    final heightProb = PoseUtilities.normalize(normalizedHipHeight, 0.0, 1.2);

    final upProbability = (angleProb * 0.7 + heightProb * 0.3);
    return {'up': upProbability, 'down': 1.0 - upProbability};
  }

  @override
  Map<String, double> calculateFormMetrics({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    final metrics = <String, double>{};

    try {
      final frontHipIdx = frontLeg == SplitSquatSide.left ? PoseLandmarkType.leftHip : PoseLandmarkType.rightHip;
      final frontKneeIdx = frontLeg == SplitSquatSide.left ? PoseLandmarkType.leftKnee : PoseLandmarkType.rightKnee;
      final frontAnkleIdx = frontLeg == SplitSquatSide.left ? PoseLandmarkType.leftAnkle : PoseLandmarkType.rightAnkle;
      final backHipIdx = frontLeg == SplitSquatSide.left ? PoseLandmarkType.rightHip : PoseLandmarkType.leftHip;

      // Front leg knee tracking
      final frontKnee = worldLandmarks[frontKneeIdx];
      final frontAnkle = worldLandmarks[frontAnkleIdx];
      final frontKneeTrackingDistance = (frontKnee.x - frontAnkle.x).abs();
      final frontKneeTrackingScore = 1.0 - (frontKneeTrackingDistance * 15).clamp(0.0, 1.0);
      metrics['front_knee_tracking'] = frontKneeTrackingScore;

      // Hip level (both hips should stay level)
      final frontHip = worldLandmarks[frontHipIdx];
      final backHip = worldLandmarks[backHipIdx];
      final hipLevelDiff = (frontHip.y - backHip.y).abs();
      final hipLevelScore = 1.0 - (hipLevelDiff * 25).clamp(0.0, 1.0);
      metrics['hip_level'] = hipLevelScore;

      // Stance length (appropriate distance between feet)
      final backAnkleIdx = frontLeg == SplitSquatSide.left ? PoseLandmarkType.rightAnkle : PoseLandmarkType.leftAnkle;
      final backAnkle = worldLandmarks[backAnkleIdx];
      final stanceLength = sqrt(pow(frontAnkle.x - backAnkle.x, 2) + pow(frontAnkle.y - backAnkle.y, 2));
      // Normalize stance length relative to leg length
      final legLength = sqrt(pow(frontHip.x - frontAnkle.x, 2) + pow(frontHip.y - frontAnkle.y, 2));
      final stanceRatio = legLength > 0 ? stanceLength / legLength : 0.0;
      final stanceScore = 1.0 - (stanceRatio - 0.8).abs().clamp(0.0, 1.0);
      metrics['stance_length'] = stanceScore;
    } catch (e) {
      metrics['front_knee_tracking'] = 0.5;
      metrics['hip_level'] = 0.5;
      metrics['stance_length'] = 0.5;
    }

    final visibilityScore = worldLandmarks.map((l) => l.visibility).reduce((a, b) => a + b) / worldLandmarks.length;
    metrics['overall_visibility'] = visibilityScore;

    return metrics;
  }
}

class CrunchClassifier extends PoseClassifier {
  @override
  Map<String, double> _calculateProbabilities({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    final nose = worldLandmarks[PoseLandmarkType.nose];
    final leftShoulder = worldLandmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = worldLandmarks[PoseLandmarkType.rightShoulder];
    final leftHip = worldLandmarks[PoseLandmarkType.leftHip];
    final rightHip = worldLandmarks[PoseLandmarkType.rightHip];

    if (nose.visibility < 0.7 || leftShoulder.visibility < 0.7 || rightShoulder.visibility < 0.7) {
      return _neutralResult();
    }

    // Calculate torso flexion angle
    final shoulderMid = PoseUtilities.getMidpoint(leftShoulder, rightShoulder);
    final hipMid = PoseUtilities.getMidpoint(leftHip, rightHip);

    // Use nose-to-shoulder vector vs shoulder-to-hip vector
    final torsoAngle = PoseUtilities.getAngle(nose, shoulderMid, hipMid);

    // In a crunch, the torso flexes forward, reducing this angle
    // UP (extended): ~160-180°, DOWN (crunched): ~120-140°
    final angleProb = 1.0 - PoseUtilities.normalize(torsoAngle, 120.0, 180.0);

    return {'up': 1.0 - angleProb, 'down': angleProb};
  }

  @override
  Map<String, double> calculateFormMetrics({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    final metrics = <String, double>{};

    try {
      final nose = worldLandmarks[PoseLandmarkType.nose];
      final leftShoulder = worldLandmarks[PoseLandmarkType.leftShoulder];
      final rightShoulder = worldLandmarks[PoseLandmarkType.rightShoulder];
      final leftHip = worldLandmarks[PoseLandmarkType.leftHip];
      final rightHip = worldLandmarks[PoseLandmarkType.rightHip];
      final leftKnee = worldLandmarks[PoseLandmarkType.leftKnee];
      final rightKnee = worldLandmarks[PoseLandmarkType.rightKnee];

      // Neck alignment (head should move with torso, not independently)
      final shoulderMid = PoseUtilities.getMidpoint(leftShoulder, rightShoulder);
      final neckAngle = PoseUtilities.getAngle(nose, shoulderMid, PoseUtilities.getMidpoint(leftHip, rightHip));
      final neckAlignmentScore = PoseUtilities.normalize(neckAngle, 140.0, 180.0);
      metrics['neck_alignment'] = neckAlignmentScore;

      // Knee stability (knees should stay bent and stable)
      final leftKneeAngle = PoseUtilities.getAngle(leftHip, leftKnee, worldLandmarks[PoseLandmarkType.leftAnkle]);
      final rightKneeAngle = PoseUtilities.getAngle(rightHip, rightKnee, worldLandmarks[PoseLandmarkType.rightAnkle]);
      final avgKneeAngle = (leftKneeAngle + rightKneeAngle) / 2;
      // Knees should be bent (~90-120 degrees)
      final kneeStabilityScore = 1.0 - (avgKneeAngle - 105.0).abs() / 45.0;
      metrics['knee_stability'] = kneeStabilityScore.clamp(0.0, 1.0);

      // Hip stability (hips should remain relatively level)
      final hipLevelDiff = (leftHip.y - rightHip.y).abs();
      final hipStabilityScore = 1.0 - (hipLevelDiff * 20).clamp(0.0, 1.0);
      metrics['hip_stability'] = hipStabilityScore;
    } catch (e) {
      metrics['neck_alignment'] = 0.5;
      metrics['knee_stability'] = 0.5;
      metrics['hip_stability'] = 0.5;
    }

    final visibilityScore = worldLandmarks.map((l) => l.visibility).reduce((a, b) => a + b) / worldLandmarks.length;
    metrics['overall_visibility'] = visibilityScore;

    return metrics;
  }
}

class ReverseCrunchClassifier extends PoseClassifier {
  @override
  Map<String, double> _calculateProbabilities({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    final leftHip = worldLandmarks[PoseLandmarkType.leftHip];
    final rightHip = worldLandmarks[PoseLandmarkType.rightHip];
    final leftKnee = worldLandmarks[PoseLandmarkType.leftKnee];
    final rightKnee = worldLandmarks[PoseLandmarkType.rightKnee];
    final leftShoulder = worldLandmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = worldLandmarks[PoseLandmarkType.rightShoulder];

    if (leftHip.visibility < 0.7 ||
        rightHip.visibility < 0.7 ||
        leftKnee.visibility < 0.7 ||
        rightKnee.visibility < 0.7) {
      return _neutralResult();
    }

    // Focus on hip-knee movement relative to torso
    final hipMid = PoseUtilities.getMidpoint(leftHip, rightHip);
    final kneeMid = PoseUtilities.getMidpoint(leftKnee, rightKnee);
    final shoulderMid = PoseUtilities.getMidpoint(leftShoulder, rightShoulder);

    // Hip flexion angle
    final hipFlexionAngle = PoseUtilities.getAngle(shoulderMid, hipMid, kneeMid);

    // In reverse crunch, knees move toward chest
    // UP (extended): ~160-180°, DOWN (knees to chest): ~60-90°
    final angleProb = 1.0 - PoseUtilities.normalize(hipFlexionAngle, 60.0, 180.0);

    return {'up': 1.0 - angleProb, 'down': angleProb};
  }

  @override
  Map<String, double> calculateFormMetrics({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    final metrics = <String, double>{};

    try {
      final leftHip = worldLandmarks[PoseLandmarkType.leftHip];
      final rightHip = worldLandmarks[PoseLandmarkType.rightHip];
      final leftKnee = worldLandmarks[PoseLandmarkType.leftKnee];
      final rightKnee = worldLandmarks[PoseLandmarkType.rightKnee];
      final leftShoulder = worldLandmarks[PoseLandmarkType.leftShoulder];
      final rightShoulder = worldLandmarks[PoseLandmarkType.rightShoulder];

      // Controlled movement (both knees should move together)
      final leftHipKneeAngle = PoseUtilities.getAngle(leftShoulder, leftHip, leftKnee);
      final rightHipKneeAngle = PoseUtilities.getAngle(rightShoulder, rightHip, rightKnee);
      final kneeSymmetryScore = 1.0 - (leftHipKneeAngle - rightHipKneeAngle).abs() / 180.0;
      metrics['knee_symmetry'] = kneeSymmetryScore.clamp(0.0, 1.0);

      // Shoulder stability (shoulders should remain stable)
      final shoulderLevelDiff = (leftShoulder.y - rightShoulder.y).abs();
      final shoulderStabilityScore = 1.0 - (shoulderLevelDiff * 25).clamp(0.0, 1.0);
      metrics['shoulder_stability'] = shoulderStabilityScore;

      // Range of motion (knees should reach toward chest)
      final hipMid = PoseUtilities.getMidpoint(leftHip, rightHip);
      final kneeMid = PoseUtilities.getMidpoint(leftKnee, rightKnee);
      final shoulderMid = PoseUtilities.getMidpoint(leftShoulder, rightShoulder);
      final romAngle = PoseUtilities.getAngle(shoulderMid, hipMid, kneeMid);
      final romScore = 1.0 - PoseUtilities.normalize(romAngle, 60.0, 180.0);
      metrics['range_of_motion'] = romScore;
    } catch (e) {
      metrics['knee_symmetry'] = 0.5;
      metrics['shoulder_stability'] = 0.5;
      metrics['range_of_motion'] = 0.5;
    }

    final visibilityScore = worldLandmarks.map((l) => l.visibility).reduce((a, b) => a + b) / worldLandmarks.length;
    metrics['overall_visibility'] = visibilityScore;

    return metrics;
  }
}

class DoubleCrunchClassifier extends PoseClassifier {
  @override
  Map<String, double> _calculateProbabilities({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    // Combines both regular crunch (torso flexion) and reverse crunch (hip flexion)
    final nose = worldLandmarks[PoseLandmarkType.nose];
    final leftShoulder = worldLandmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = worldLandmarks[PoseLandmarkType.rightShoulder];
    final leftHip = worldLandmarks[PoseLandmarkType.leftHip];
    final rightHip = worldLandmarks[PoseLandmarkType.rightHip];
    final leftKnee = worldLandmarks[PoseLandmarkType.leftKnee];
    final rightKnee = worldLandmarks[PoseLandmarkType.rightKnee];

    if (nose.visibility < 0.6 || leftShoulder.visibility < 0.7 || rightShoulder.visibility < 0.7) {
      return _neutralResult();
    }

    final shoulderMid = PoseUtilities.getMidpoint(leftShoulder, rightShoulder);
    final hipMid = PoseUtilities.getMidpoint(leftHip, rightHip);
    final kneeMid = PoseUtilities.getMidpoint(leftKnee, rightKnee);

    // Torso flexion (like regular crunch)
    final torsoAngle = PoseUtilities.getAngle(nose, shoulderMid, hipMid);
    final torsoFlexion = 1.0 - PoseUtilities.normalize(torsoAngle, 120.0, 180.0);

    // Hip flexion (like reverse crunch)
    final hipAngle = PoseUtilities.getAngle(shoulderMid, hipMid, kneeMid);
    final hipFlexion = 1.0 - PoseUtilities.normalize(hipAngle, 60.0, 180.0);

    // Both should happen together for double crunch
    final combinedFlexion = (torsoFlexion + hipFlexion) / 2;

    return {'up': 1.0 - combinedFlexion, 'down': combinedFlexion};
  }

  @override
  Map<String, double> calculateFormMetrics({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    final metrics = <String, double>{};

    try {
      final nose = worldLandmarks[PoseLandmarkType.nose];
      final leftShoulder = worldLandmarks[PoseLandmarkType.leftShoulder];
      final rightShoulder = worldLandmarks[PoseLandmarkType.rightShoulder];
      final leftHip = worldLandmarks[PoseLandmarkType.leftHip];
      final rightHip = worldLandmarks[PoseLandmarkType.rightHip];
      final leftKnee = worldLandmarks[PoseLandmarkType.leftKnee];
      final rightKnee = worldLandmarks[PoseLandmarkType.rightKnee];

      final shoulderMid = PoseUtilities.getMidpoint(leftShoulder, rightShoulder);
      final hipMid = PoseUtilities.getMidpoint(leftHip, rightHip);
      final kneeMid = PoseUtilities.getMidpoint(leftKnee, rightKnee);

      // Coordination (both movements should happen together)
      final torsoAngle = PoseUtilities.getAngle(nose, shoulderMid, hipMid);
      final hipAngle = PoseUtilities.getAngle(shoulderMid, hipMid, kneeMid);
      final torsoFlexion = 1.0 - PoseUtilities.normalize(torsoAngle, 120.0, 180.0);
      final hipFlexion = 1.0 - PoseUtilities.normalize(hipAngle, 60.0, 180.0);
      final coordinationScore = 1.0 - (torsoFlexion - hipFlexion).abs();
      metrics['movement_coordination'] = coordinationScore.clamp(0.0, 1.0);

      // Bilateral symmetry (both sides moving together)
      final leftSideAngle = PoseUtilities.getAngle(nose, leftShoulder, leftKnee);
      final rightSideAngle = PoseUtilities.getAngle(nose, rightShoulder, rightKnee);
      final symmetryScore = 1.0 - (leftSideAngle - rightSideAngle).abs() / 180.0;
      metrics['bilateral_symmetry'] = symmetryScore.clamp(0.0, 1.0);

      // Full range activation
      final combinedFlexion = (torsoFlexion + hipFlexion) / 2;
      metrics['full_range_activation'] = combinedFlexion;
    } catch (e) {
      metrics['movement_coordination'] = 0.5;
      metrics['bilateral_symmetry'] = 0.5;
      metrics['full_range_activation'] = 0.5;
    }

    final visibilityScore = worldLandmarks.map((l) => l.visibility).reduce((a, b) => a + b) / worldLandmarks.length;
    metrics['overall_visibility'] = visibilityScore;

    return metrics;
  }
}

class SupermanClassifier extends PoseClassifier {
  @override
  Map<String, double> _calculateProbabilities({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    final nose = worldLandmarks[PoseLandmarkType.nose];
    final leftShoulder = worldLandmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = worldLandmarks[PoseLandmarkType.rightShoulder];
    final leftHip = worldLandmarks[PoseLandmarkType.leftHip];
    final rightHip = worldLandmarks[PoseLandmarkType.rightHip];

    if (nose.visibility < 0.6 || leftShoulder.visibility < 0.7 || rightShoulder.visibility < 0.7) {
      return _neutralResult();
    }

    final shoulderMid = PoseUtilities.getMidpoint(leftShoulder, rightShoulder);
    final hipMid = PoseUtilities.getMidpoint(leftHip, rightHip);

    // Back extension angle (opposite of crunch)
    final backAngle = PoseUtilities.getAngle(nose, shoulderMid, hipMid);

    // In superman, back extends, increasing this angle
    // DOWN (lying flat): ~160-180°, UP (extended): ~180-200° (but clamped)
    // We look for extension beyond neutral
    final extensionProb = backAngle > 170.0 ? PoseUtilities.normalize(backAngle, 170.0, 200.0) : 0.0;

    return {'up': extensionProb, 'down': 1.0 - extensionProb};
  }

  @override
  Map<String, double> calculateFormMetrics({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    final metrics = <String, double>{};

    try {
      final nose = worldLandmarks[PoseLandmarkType.nose];
      final leftShoulder = worldLandmarks[PoseLandmarkType.leftShoulder];
      final rightShoulder = worldLandmarks[PoseLandmarkType.rightShoulder];
      final leftHip = worldLandmarks[PoseLandmarkType.leftHip];
      final rightHip = worldLandmarks[PoseLandmarkType.rightHip];
      final leftWrist = worldLandmarks[PoseLandmarkType.leftWrist];
      final rightWrist = worldLandmarks[PoseLandmarkType.rightWrist];
      final leftAnkle = worldLandmarks[PoseLandmarkType.leftAnkle];
      final rightAnkle = worldLandmarks[PoseLandmarkType.rightAnkle];

      // Spinal alignment (head, shoulders, hips should form smooth curve)
      final shoulderMid = PoseUtilities.getMidpoint(leftShoulder, rightShoulder);
      final hipMid = PoseUtilities.getMidpoint(leftHip, rightHip);
      final spinalAngle = PoseUtilities.getAngle(nose, shoulderMid, hipMid);
      final spinalAlignmentScore = PoseUtilities.normalize(spinalAngle, 170.0, 200.0);
      metrics['spinal_alignment'] = spinalAlignmentScore;

      // Arm extension (arms should be extended forward)
      final wristMid = PoseUtilities.getMidpoint(leftWrist, rightWrist);
      final armExtensionDistance = sqrt(pow(shoulderMid.x - wristMid.x, 2) + pow(shoulderMid.y - wristMid.y, 2));
      // Normalize based on typical arm span
      final armExtensionScore = PoseUtilities.normalize(armExtensionDistance, 0.3, 0.8);
      metrics['arm_extension'] = armExtensionScore;

      // Leg extension (legs should be extended backward and lifted)
      final ankleMid = PoseUtilities.getMidpoint(leftAnkle, rightAnkle);
      final legExtensionDistance = sqrt(pow(hipMid.x - ankleMid.x, 2) + pow(hipMid.y - ankleMid.y, 2));
      final legExtensionScore = PoseUtilities.normalize(legExtensionDistance, 0.4, 1.0);
      metrics['leg_extension'] = legExtensionScore;

      // Bilateral symmetry (both sides should lift evenly)
      final leftArmAngle = PoseUtilities.getAngle(leftShoulder, leftShoulder, leftWrist);
      final rightArmAngle = PoseUtilities.getAngle(rightShoulder, rightShoulder, rightWrist);
      final armSymmetryScore = 1.0 - (leftArmAngle - rightArmAngle).abs() / 180.0;
      metrics['bilateral_symmetry'] = armSymmetryScore.clamp(0.0, 1.0);
    } catch (e) {
      metrics['spinal_alignment'] = 0.5;
      metrics['arm_extension'] = 0.5;
      metrics['leg_extension'] = 0.5;
      metrics['bilateral_symmetry'] = 0.5;
    }

    final visibilityScore = worldLandmarks.map((l) => l.visibility).reduce((a, b) => a + b) / worldLandmarks.length;
    metrics['overall_visibility'] = visibilityScore;

    return metrics;
  }
}
