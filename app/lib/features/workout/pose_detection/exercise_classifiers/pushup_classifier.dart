part of 'exercise_classifiers.dart';

enum PushUpType { standard, knee, wall, incline, decline, diamond, wide }

class PushUpClassifier extends PoseClassifier {
  final PushUpType type;

  PushUpClassifier({this.type = PushUpType.standard, super.smoothingWindow});

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

    // Check visibility with consistent threshold
    const double visibilityThreshold = 0.7;
    if (shoulder3D.visibility < visibilityThreshold ||
        elbow3D.visibility < visibilityThreshold ||
        wrist3D.visibility < visibilityThreshold) {
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
      // Overlap region - use smoother interpolation with safety checks
      final range = angleThresholds['upMin']! - angleThresholds['downMax']!;
      if (range <= 0) {
        // Safety check: if range is invalid, return neutral
        return _neutralResult();
      }
      angleProb = (elbowAngle - angleThresholds['downMax']!) / range;
      // Apply sigmoid-like function for smoother transition
      angleProb = angleProb * angleProb; // Square to push toward extremes
      angleProb = angleProb.clamp(0.0, 1.0); // Ensure bounds
    }

    // Signal 2: Shoulder Height relative to Wrist (Secondary, variation-adjusted)
    final shoulderHeight = PoseUtilities.getVerticalDistance(shoulder2D, wrist2D);
    final torsoHeight = PoseUtilities.getVerticalDistance(shoulder2D, hip2D);

    // Safety check for torso height
    if (torsoHeight < 0.01) return _neutralResult();

    final normalizedShoulderHeight = shoulderHeight / torsoHeight;
    // Invert the height signal: higher height = more likely DOWN position
    final heightProb =
        1.0 - PoseUtilities.normalize(normalizedShoulderHeight, heightRanges['min']!, heightRanges['max']!);

    // Weight angle more heavily since it's more reliable, with safety bounds
    final upProbability = (angleProb * 0.9 + heightProb * 0.1).clamp(0.0, 1.0);
    return {'up': upProbability, 'down': 1.0 - upProbability};
  }

  /// Returns variation-specific angle thresholds for elbow angle classification
  Map<String, double> _getAngleThresholds() {
    switch (type) {
      case PushUpType.standard:
        return {'upMin': 150.0, 'downMax': 120.0}; // Standard range of motion
      case PushUpType.knee:
        return {'upMin': 150.0, 'downMax': 120.0}; // Similar to standard but may be more forgiving
      case PushUpType.wall:
        return {'upMin': 140.0, 'downMax': 130.0}; // Smaller range for wall push-ups
      case PushUpType.incline:
        return {'upMin': 155.0, 'downMax': 125.0}; // Slightly larger range due to angle
      case PushUpType.decline:
        return {'upMin': 145.0, 'downMax': 115.0}; // Slightly smaller range due to gravity assist
      case PushUpType.diamond:
        return {'upMin': 145.0, 'downMax': 115.0}; // Narrower hand position affects elbow mechanics
      case PushUpType.wide:
        return {'upMin': 155.0, 'downMax': 125.0}; // Wider hand position affects elbow mechanics
    }
  }

  /// Returns variation-specific height normalization ranges
  Map<String, double> _getHeightRanges() {
    switch (type) {
      case PushUpType.standard:
        return {'min': 1.5, 'max': 6.0}; // Standard torso-relative ranges
      case PushUpType.knee:
        return {'min': 1.5, 'max': 6.0}; // Similar to standard but adapted for knee position
      case PushUpType.wall:
        return {'min': 0.5, 'max': 3.0}; // Much smaller height variation for wall push-ups
      case PushUpType.incline:
        return {'min': 1.0, 'max': 4.5}; // Reduced range due to incline angle
      case PushUpType.decline:
        return {'min': 2.0, 'max': 7.5}; // Increased range due to decline angle
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
      // Check which side of the body is facing the camera
      // This allows us to adapt our landmark requirements and calculations
      // to prioritize the more visible side, improving accuracy
      final isLeftVisible = PoseUtilities.isLeftBodyVisible(worldLandmarks);

      // Check landmark availability first - adapt based on visible side
      // We only require high visibility for landmarks on the primary (more visible) side
      const double minVisibility = 0.6;
      final requiredLandmarks = _getRequiredLandmarks(isLeftVisible);

      if (!requiredLandmarks.every((idx) => worldLandmarks[idx].visibility >= minVisibility)) {
        // Return default metrics if key landmarks are not visible enough
        return _getDefaultMetrics();
      }

      final leftShoulder = worldLandmarks[PoseLandmarkType.leftShoulder];
      final rightShoulder = worldLandmarks[PoseLandmarkType.rightShoulder];
      final leftHip = worldLandmarks[PoseLandmarkType.leftHip];
      final rightHip = worldLandmarks[PoseLandmarkType.rightHip];

      // Body alignment (straight line from shoulders to contact points)
      final shoulderMid = PoseUtilities.getMidpoint(leftShoulder, rightShoulder);
      final hipMid = PoseUtilities.getMidpoint(leftHip, rightHip);

      // Different alignment calculations based on push-up type
      _calculateBodyAlignment(metrics, shoulderMid, hipMid, worldLandmarks, isLeftVisible);

      // Hand width evaluation (variation-specific)
      _calculateHandWidth(metrics, imageLandmarks, isLeftVisible);

      // Wrist positioning (should be roughly under shoulders for most variations)
      _calculateWristPositioning(metrics, imageLandmarks, isLeftVisible);
    } catch (e) {
      // More intelligent fallback values based on push-up type
      return _getDefaultMetrics();
    }

    // Add overall visibility
    final visibilityScore = worldLandmarks.map((l) => l.visibility).reduce((a, b) => a + b) / worldLandmarks.length;
    metrics['overall_visibility'] = visibilityScore;

    return metrics;
  }

  /// Calculate body alignment metrics based on push-up type
  void _calculateBodyAlignment(
    Map<String, double> metrics,
    PoseLandmark shoulderMid,
    PoseLandmark hipMid,
    List<PoseLandmark> worldLandmarks,
    bool isLeftVisible,
  ) {
    switch (type) {
      case PushUpType.knee:
        // Prefer visible side for knee landmarks, fallback to midpoint if both visible
        final leftKnee = worldLandmarks[PoseLandmarkType.leftKnee];
        final rightKnee = worldLandmarks[PoseLandmarkType.rightKnee];

        if (leftKnee.visibility >= 0.6 && rightKnee.visibility >= 0.6) {
          // Both knees visible - use midpoint
          final kneeMid = PoseUtilities.getMidpoint(leftKnee, rightKnee);
          final bodyAngle = PoseUtilities.getAngle(shoulderMid, hipMid, kneeMid);
          final targetAngle = 155.0;
          final alignmentScore = 1.0 - (targetAngle - bodyAngle).abs() / 45.0;
          metrics['body_alignment'] = alignmentScore.clamp(0.0, 1.0);
        } else if (isLeftVisible && leftKnee.visibility >= 0.6) {
          // Use left knee when left side is more visible
          final bodyAngle = PoseUtilities.getAngle(shoulderMid, hipMid, leftKnee);
          final targetAngle = 155.0;
          final alignmentScore = 1.0 - (targetAngle - bodyAngle).abs() / 45.0;
          metrics['body_alignment'] = alignmentScore.clamp(0.0, 1.0);
        } else if (!isLeftVisible && rightKnee.visibility >= 0.6) {
          // Use right knee when right side is more visible
          final bodyAngle = PoseUtilities.getAngle(shoulderMid, hipMid, rightKnee);
          final targetAngle = 155.0;
          final alignmentScore = 1.0 - (targetAngle - bodyAngle).abs() / 45.0;
          metrics['body_alignment'] = alignmentScore.clamp(0.0, 1.0);
        } else {
          metrics['body_alignment'] = 0.5; // Fallback if no knees visible enough
        }
        break;

      case PushUpType.wall:
        // For wall push-ups, body should be at an angle to the wall
        final leftAnkle = worldLandmarks[PoseLandmarkType.leftAnkle];
        final rightAnkle = worldLandmarks[PoseLandmarkType.rightAnkle];
        final targetAngle = 165.0;

        if (leftAnkle.visibility >= 0.6 && rightAnkle.visibility >= 0.6) {
          final ankleMid = PoseUtilities.getMidpoint(leftAnkle, rightAnkle);
          final bodyAngle = PoseUtilities.getAngle(shoulderMid, hipMid, ankleMid);
          final alignmentScore = 1.0 - (targetAngle - bodyAngle).abs() / 30.0;
          metrics['body_alignment'] = alignmentScore.clamp(0.0, 1.0);
        } else if (isLeftVisible && leftAnkle.visibility >= 0.6) {
          final bodyAngle = PoseUtilities.getAngle(shoulderMid, hipMid, leftAnkle);
          final alignmentScore = 1.0 - (targetAngle - bodyAngle).abs() / 30.0;
          metrics['body_alignment'] = alignmentScore.clamp(0.0, 1.0);
        } else if (!isLeftVisible && rightAnkle.visibility >= 0.6) {
          final bodyAngle = PoseUtilities.getAngle(shoulderMid, hipMid, rightAnkle);
          final alignmentScore = 1.0 - (targetAngle - bodyAngle).abs() / 30.0;
          metrics['body_alignment'] = alignmentScore.clamp(0.0, 1.0);
        } else {
          metrics['body_alignment'] = 0.5;
        }
        break;

      case PushUpType.incline:
      case PushUpType.decline:
        // For incline/decline, check body straightness with adjusted expectations
        final leftAnkle = worldLandmarks[PoseLandmarkType.leftAnkle];
        final rightAnkle = worldLandmarks[PoseLandmarkType.rightAnkle];

        if (leftAnkle.visibility >= 0.6 && rightAnkle.visibility >= 0.6) {
          final ankleMid = PoseUtilities.getMidpoint(leftAnkle, rightAnkle);
          final bodyAngle = PoseUtilities.getAngle(shoulderMid, hipMid, ankleMid);
          final alignmentScore = 1.0 - (175.0 - bodyAngle).abs() / 50.0;
          metrics['body_alignment'] = alignmentScore.clamp(0.0, 1.0);
        } else if (isLeftVisible && leftAnkle.visibility >= 0.6) {
          final bodyAngle = PoseUtilities.getAngle(shoulderMid, hipMid, leftAnkle);
          final alignmentScore = 1.0 - (175.0 - bodyAngle).abs() / 50.0;
          metrics['body_alignment'] = alignmentScore.clamp(0.0, 1.0);
        } else if (!isLeftVisible && rightAnkle.visibility >= 0.6) {
          final bodyAngle = PoseUtilities.getAngle(shoulderMid, hipMid, rightAnkle);
          final alignmentScore = 1.0 - (175.0 - bodyAngle).abs() / 50.0;
          metrics['body_alignment'] = alignmentScore.clamp(0.0, 1.0);
        } else {
          metrics['body_alignment'] = 0.5;
        }
        break;

      default:
        // Standard, diamond, wide push-ups - straight body line
        final leftAnkle = worldLandmarks[PoseLandmarkType.leftAnkle];
        final rightAnkle = worldLandmarks[PoseLandmarkType.rightAnkle];

        if (leftAnkle.visibility >= 0.6 && rightAnkle.visibility >= 0.6) {
          final ankleMid = PoseUtilities.getMidpoint(leftAnkle, rightAnkle);
          final bodyAngle = PoseUtilities.getAngle(shoulderMid, hipMid, ankleMid);
          final alignmentScore = 1.0 - (180.0 - bodyAngle).abs() / 45.0;
          metrics['body_alignment'] = alignmentScore.clamp(0.0, 1.0);
        } else if (isLeftVisible && leftAnkle.visibility >= 0.6) {
          final bodyAngle = PoseUtilities.getAngle(shoulderMid, hipMid, leftAnkle);
          final alignmentScore = 1.0 - (180.0 - bodyAngle).abs() / 45.0;
          metrics['body_alignment'] = alignmentScore.clamp(0.0, 1.0);
        } else if (!isLeftVisible && rightAnkle.visibility >= 0.6) {
          final bodyAngle = PoseUtilities.getAngle(shoulderMid, hipMid, rightAnkle);
          final alignmentScore = 1.0 - (180.0 - bodyAngle).abs() / 45.0;
          metrics['body_alignment'] = alignmentScore.clamp(0.0, 1.0);
        } else {
          metrics['body_alignment'] = 0.5;
        }
    }
  }

  /// Calculate hand width metrics
  void _calculateHandWidth(Map<String, double> metrics, List<PoseLandmark> imageLandmarks, bool isLeftVisible) {
    final leftWrist = imageLandmarks[PoseLandmarkType.leftWrist];
    final rightWrist = imageLandmarks[PoseLandmarkType.rightWrist];
    final leftShoulderImg = imageLandmarks[PoseLandmarkType.leftShoulder];
    final rightShoulderImg = imageLandmarks[PoseLandmarkType.rightShoulder];

    final handWidth = (leftWrist.x - rightWrist.x).abs();
    final shoulderWidth = (leftShoulderImg.x - rightShoulderImg.x).abs();

    if (shoulderWidth <= 0.0) {
      metrics['hand_width'] = 0.5; // Fallback if shoulder width can't be determined
      return;
    }

    final widthRatio = handWidth / shoulderWidth;

    double widthScore;
    switch (type) {
      case PushUpType.diamond:
        // Diamond push-ups: hands should be close together (ratio < 0.5)
        final idealRatio = 0.3;
        final deviation = (widthRatio - idealRatio).abs();
        widthScore = (1.0 - deviation).clamp(0.0, 1.0);
        break;
      case PushUpType.wide:
        // Wide push-ups: hands should be wider than shoulders (ratio > 1.5)
        final idealRatio = 1.8;
        final deviation = (widthRatio - idealRatio).abs();
        widthScore = (1.0 - deviation).clamp(0.0, 1.0);
        break;
      default:
        // Standard, knee, wall, incline, decline: hands slightly wider than shoulders
        final idealRatio = 1.25;
        final deviation = (widthRatio - idealRatio).abs();
        widthScore = (1.0 - deviation).clamp(0.0, 1.0);
    }
    metrics['hand_width'] = widthScore;
  }

  /// Calculate wrist positioning metrics
  void _calculateWristPositioning(Map<String, double> metrics, List<PoseLandmark> imageLandmarks, bool isLeftVisible) {
    final leftWrist = imageLandmarks[PoseLandmarkType.leftWrist];
    final rightWrist = imageLandmarks[PoseLandmarkType.rightWrist];
    final leftShoulderImg = imageLandmarks[PoseLandmarkType.leftShoulder];
    final rightShoulderImg = imageLandmarks[PoseLandmarkType.rightShoulder];

    // Check visibility of wrist landmarks
    const double minWristVisibility = 0.5;
    final leftWristVisible = leftWrist.visibility >= minWristVisibility;
    final rightWristVisible = rightWrist.visibility >= minWristVisibility;

    if (leftWristVisible && rightWristVisible) {
      // Both wrists visible - calculate average
      final leftWristShoulderDistance = sqrt(
        pow(leftWrist.x - leftShoulderImg.x, 2) + pow(leftWrist.y - leftShoulderImg.y, 2),
      );
      final rightWristShoulderDistance = sqrt(
        pow(rightWrist.x - rightShoulderImg.x, 2) + pow(rightWrist.y - rightShoulderImg.y, 2),
      );
      final avgWristShoulderDistance = (leftWristShoulderDistance + rightWristShoulderDistance) / 2;
      final wristScore = (1.0 - (avgWristShoulderDistance * 2.5)).clamp(0.0, 1.0);
      metrics['wrist_positioning'] = wristScore;
    } else if (isLeftVisible && leftWristVisible) {
      // Use left wrist when left side is more visible
      final leftWristShoulderDistance = sqrt(
        pow(leftWrist.x - leftShoulderImg.x, 2) + pow(leftWrist.y - leftShoulderImg.y, 2),
      );
      final wristScore = (1.0 - (leftWristShoulderDistance * 2.5)).clamp(0.0, 1.0);
      metrics['wrist_positioning'] = wristScore;
    } else if (!isLeftVisible && rightWristVisible) {
      // Use right wrist when right side is more visible
      final rightWristShoulderDistance = sqrt(
        pow(rightWrist.x - rightShoulderImg.x, 2) + pow(rightWrist.y - rightShoulderImg.y, 2),
      );
      final wristScore = (1.0 - (rightWristShoulderDistance * 2.5)).clamp(0.0, 1.0);
      metrics['wrist_positioning'] = wristScore;
    } else {
      // Fallback when no wrists are sufficiently visible
      metrics['wrist_positioning'] = 0.5;
    }
  }

  /// Get default metrics when calculation fails or landmarks are not visible
  Map<String, double> _getDefaultMetrics() {
    return {'body_alignment': 0.5, 'wrist_positioning': 0.5, 'hand_width': 0.5, 'overall_visibility': 0.5};
  }

  /// Get required landmarks based on which side of the body is visible
  List<int> _getRequiredLandmarks(bool isLeftVisible) {
    // Only require landmarks from the primary (more visible) side
    // This allows detection even when one side is heavily occluded
    if (isLeftVisible) {
      return [
        PoseLandmarkType.leftShoulder,
        PoseLandmarkType.leftHip,
        PoseLandmarkType.leftElbow,
        PoseLandmarkType.leftWrist,
      ];
    } else {
      return [
        PoseLandmarkType.rightShoulder,
        PoseLandmarkType.rightHip,
        PoseLandmarkType.rightElbow,
        PoseLandmarkType.rightWrist,
      ];
    }
  }
}
