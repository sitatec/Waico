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
