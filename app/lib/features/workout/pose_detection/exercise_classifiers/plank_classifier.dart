part of 'exercise_classifiers.dart';

class PlankClassifier extends ExerciseClassifier {
  @override
  bool get isDurationBased => true;

  @override
  Map<String, double> _calculateProbabilities({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    // Check which side is more visible (user is sideways during plank)
    final isLeftVisible = PoseUtilities.isLeftBodyVisible(worldLandmarks);

    // Choose the visible side for calculations (isLeftVisible returns true if left is more visible)
    final shoulderType = isLeftVisible ? PoseLandmarkType.leftShoulder : PoseLandmarkType.rightShoulder;
    final elbowType = isLeftVisible ? PoseLandmarkType.leftElbow : PoseLandmarkType.rightElbow;
    final wristType = isLeftVisible ? PoseLandmarkType.leftWrist : PoseLandmarkType.rightWrist;
    final hipType = isLeftVisible ? PoseLandmarkType.leftHip : PoseLandmarkType.rightHip;
    final kneeType = isLeftVisible ? PoseLandmarkType.leftKnee : PoseLandmarkType.rightKnee;
    final ankleType = isLeftVisible ? PoseLandmarkType.leftAnkle : PoseLandmarkType.rightAnkle;

    // Get landmarks for the visible side
    final shoulder = worldLandmarks[shoulderType];
    final elbow = worldLandmarks[elbowType];
    final wrist = worldLandmarks[wristType];
    final hip = worldLandmarks[hipType];
    final knee = worldLandmarks[kneeType];
    final ankle = worldLandmarks[ankleType];

    // Check visibility of key landmarks for the selected side
    const double visibilityThreshold = 0.7;
    if (shoulder.visibility < visibilityThreshold ||
        hip.visibility < visibilityThreshold ||
        ankle.visibility < visibilityThreshold ||
        elbow.visibility < visibilityThreshold ||
        wrist.visibility < visibilityThreshold ||
        knee.visibility < visibilityThreshold) {
      return _neutralResult();
    }

    // --- Granular Algorithm ---
    // 1. Body Alignment (Primary): Check if the body forms a straight line
    // 2. Arm Support Angle (Secondary): Elbow angle for proper support
    // 3. Hip Height (Tertiary): Hip should not sag or pike

    // Signal 1: Body Alignment - Calculate the straightness of the body line
    // For plank, we use the visible side to check alignment
    final bodyAngle = PoseUtilities.getAngle(shoulder, hip, ankle);
    // In a good plank, body should be straight (close to 180 degrees)
    final alignmentProb = PoseUtilities.normalize(bodyAngle, 160.0, 180.0);

    // Signal 2: Arm Support Angle
    final armAngle = PoseUtilities.getAngle(shoulder, elbow, wrist);
    // Arms should be relatively straight in plank (160-180 degrees)
    final armAngleProb = PoseUtilities.normalize(armAngle, 140.0, 180.0);

    // Signal 3: Hip Height Consistency
    // Check if hips are neither too high (pike) nor too low (sag)
    final shoulderHipDistance = sqrt(pow(shoulder.x - hip.x, 2) + pow(shoulder.y - hip.y, 2));
    final hipAnkleDistance = sqrt(pow(hip.x - ankle.x, 2) + pow(hip.y - ankle.y, 2));
    final totalBodyLength = shoulderHipDistance + hipAnkleDistance;

    if (totalBodyLength < 0.01) return _neutralResult();

    // Check vertical alignment - hip should be roughly in line with shoulder and ankle
    final shoulderToAnkleDistance = sqrt(pow(shoulder.x - ankle.x, 2) + pow(shoulder.y - ankle.y, 2));
    final heightConsistency = shoulderToAnkleDistance / totalBodyLength;
    final heightProb = PoseUtilities.normalize(heightConsistency, 0.85, 1.0);

    // Combine probabilities - alignment is most important for plank
    final plankProbability = (alignmentProb * 0.6 + armAngleProb * 0.25 + heightProb * 0.15);

    return {'up': plankProbability, 'down': 1.0 - plankProbability};
  }

  @override
  Map<String, dynamic> calculateFormMetrics({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
    String? position,
  }) {
    final metrics = <String, double>{};

    try {
      final leftShoulder = worldLandmarks[PoseLandmarkType.leftShoulder];
      final rightShoulder = worldLandmarks[PoseLandmarkType.rightShoulder];
      final leftHip = worldLandmarks[PoseLandmarkType.leftHip];
      final rightHip = worldLandmarks[PoseLandmarkType.rightHip];
      final leftAnkle = worldLandmarks[PoseLandmarkType.leftAnkle];
      final rightAnkle = worldLandmarks[PoseLandmarkType.rightAnkle];

      // Body alignment score
      final shoulderMidpoint = PoseUtilities.getMidpoint(leftShoulder, rightShoulder);
      final hipMidpoint = PoseUtilities.getMidpoint(leftHip, rightHip);
      final ankleMidpoint = PoseUtilities.getMidpoint(leftAnkle, rightAnkle);

      final bodyAngle = PoseUtilities.getAngle(shoulderMidpoint, hipMidpoint, ankleMidpoint);
      final alignmentScore = PoseUtilities.normalize(bodyAngle, 160.0, 180.0);
      metrics['body_alignment'] = alignmentScore;

      // Hip sagging detection
      final shoulderHeight = shoulderMidpoint.y;
      final hipHeight = hipMidpoint.y;
      final ankleHeight = ankleMidpoint.y;

      // Calculate expected hip height based on straight line interpolation
      final bodyLength = sqrt(
        pow(shoulderMidpoint.x - ankleMidpoint.x, 2) + pow(shoulderMidpoint.y - ankleMidpoint.y, 2),
      );
      final shoulderToHipLength = sqrt(
        pow(shoulderMidpoint.x - hipMidpoint.x, 2) + pow(shoulderMidpoint.y - hipMidpoint.y, 2),
      );

      if (bodyLength > 0.01) {
        final expectedHipHeight = shoulderHeight + (ankleHeight - shoulderHeight) * (shoulderToHipLength / bodyLength);
        final hipDeviation = (hipHeight - expectedHipHeight).abs();
        final hipSagScore = 1.0 - PoseUtilities.normalize(hipDeviation, 0.0, 0.1);
        metrics['hip_stability'] = hipSagScore;
      } else {
        metrics['hip_stability'] = 0.5;
      }

      // Note: Arm positioning metrics removed due to sideways camera orientation
      // These measurements are unreliable when user is facing sideways

      // Core engagement (derived from body stability)
      final coreEngagementScore = metrics['body_alignment']! * metrics['hip_stability']!;
      metrics['core_engagement'] = coreEngagementScore;
    } catch (e) {
      // Fallback values on error
      metrics['body_alignment'] = 0.5;
      metrics['hip_stability'] = 0.5;
      metrics['core_engagement'] = 0.5;
    }

    // Add overall visibility
    final visibilityScore = worldLandmarks.map((l) => l.visibility).reduce((a, b) => a + b) / worldLandmarks.length;
    metrics['overall_visibility'] = visibilityScore;

    return _generateFeedbackMessages(formMetrics: metrics);
  }

  Map<String, dynamic> _generateFeedbackMessages({required Map<String, double> formMetrics}) {
    final feedback = <String, dynamic>{};

    // Body alignment feedback
    if (formMetrics['body_alignment'] != null) {
      final alignment = formMetrics['body_alignment']!;
      feedback['body_alignment'] = <String, dynamic>{'score': alignment};
      if (alignment < 0.7) {
        feedback['body_alignment']['message'] =
            'Should maintain a straight line from head to heels - avoid arching or rounding the back';
      }
    }

    // Hip stability feedback
    if (formMetrics['hip_stability'] != null) {
      final hipStability = formMetrics['hip_stability']!;
      feedback['hip_stability'] = <String, dynamic>{'score': hipStability};
      if (hipStability < 0.7) {
        feedback['hip_stability']['message'] = 'Should keep hips level - avoid sagging down or piking up too high';
      }
    }

    // Note: Arm positioning and arm straightness feedback removed due to sideways camera orientation
    // These measurements are unreliable when user is facing sideways

    // Core engagement feedback
    if (formMetrics['core_engagement'] != null) {
      final coreEngagement = formMetrics['core_engagement']!;
      feedback['core_engagement'] = <String, dynamic>{'score': coreEngagement};
      if (coreEngagement < 0.7) {
        feedback['core_engagement']['message'] = 'Should engage core muscles to maintain stability and proper form';
      }
    }

    // Overall visibility feedback
    if (formMetrics['overall_visibility'] != null) {
      final visibility = formMetrics['overall_visibility']!;
      feedback['overall_visibility'] = <String, dynamic>{'score': visibility};
      if (visibility < 0.7) {
        feedback['overall_visibility']['message'] = 'Should ensure the whole body is clearly visible in the camera';
      }
    }

    return feedback;
  }
}

enum SidePlankSide { left, right }

class SidePlankClassifier extends ExerciseClassifier {
  final SidePlankSide supportingSide;

  SidePlankClassifier({required this.supportingSide});

  @override
  bool get isDurationBased => true;

  @override
  Map<String, double> _calculateProbabilities({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    // For side plank, we use the supporting side specified
    final supportingShoulder = supportingSide == SidePlankSide.left
        ? worldLandmarks[PoseLandmarkType.leftShoulder]
        : worldLandmarks[PoseLandmarkType.rightShoulder];
    final supportingElbow = supportingSide == SidePlankSide.left
        ? worldLandmarks[PoseLandmarkType.leftElbow]
        : worldLandmarks[PoseLandmarkType.rightElbow];
    final supportingWrist = supportingSide == SidePlankSide.left
        ? worldLandmarks[PoseLandmarkType.leftWrist]
        : worldLandmarks[PoseLandmarkType.rightWrist];

    final leftHip = worldLandmarks[PoseLandmarkType.leftHip];
    final rightHip = worldLandmarks[PoseLandmarkType.rightHip];
    final leftAnkle = worldLandmarks[PoseLandmarkType.leftAnkle];
    final rightAnkle = worldLandmarks[PoseLandmarkType.rightAnkle];

    // Check visibility of key landmarks with threshold
    const double visibilityThreshold = 0.7;
    if (supportingShoulder.visibility < visibilityThreshold ||
        supportingElbow.visibility < visibilityThreshold ||
        leftHip.visibility < visibilityThreshold ||
        rightHip.visibility < visibilityThreshold ||
        leftAnkle.visibility < visibilityThreshold ||
        rightAnkle.visibility < visibilityThreshold) {
      return _neutralResult();
    }

    // --- Side Plank Algorithm ---
    // 1. Body Alignment (Primary): Straight line from head to feet when viewed from side
    // 2. Hip Elevation (Secondary): Hips should be lifted off the ground
    // 3. Arm Support (Tertiary): Supporting arm should be stable

    // Signal 1: Body Alignment - Check if body forms a straight line
    final hipMidpoint = PoseUtilities.getMidpoint(leftHip, rightHip);
    final ankleMidpoint = PoseUtilities.getMidpoint(leftAnkle, rightAnkle);

    // Calculate body alignment using shoulder-hip-ankle angle
    final bodyAngle = PoseUtilities.getAngle(supportingShoulder, hipMidpoint, ankleMidpoint);
    final alignmentProb = PoseUtilities.normalize(bodyAngle, 160.0, 180.0);

    // Signal 2: Hip Elevation - Hips should be elevated in side plank
    // Calculate hip height relative to supporting elbow/wrist
    final supportingArmPoint = supportingWrist.visibility > 0.7 ? supportingWrist : supportingElbow;
    final hipElevation = (supportingArmPoint.y - hipMidpoint.y);

    // In side plank, hips should be above the supporting arm
    final elevationProb = PoseUtilities.normalize(hipElevation, -0.2, 0.3);

    // Signal 3: Support Stability - Check supporting arm angle
    double supportStabilityProb = 0.5;
    if (supportingWrist.visibility > 0.7) {
      final supportArmAngle = PoseUtilities.getAngle(supportingShoulder, supportingElbow, supportingWrist);
      // Supporting arm should be relatively straight (120-180 degrees)
      supportStabilityProb = PoseUtilities.normalize(supportArmAngle, 120.0, 180.0);
    }

    // Signal 4: Lateral Stability - Check if body is not twisting
    final hipWidth = (leftHip.x - rightHip.x).abs();
    final ankleWidth = (leftAnkle.x - rightAnkle.x).abs();
    double lateralStabilityProb = 0.8; // Default good score

    if (hipWidth > 0.01 && ankleWidth > 0.01) {
      final widthRatio = ankleWidth / hipWidth;
      // In side plank, ankle width should be similar to hip width (not too spread)
      lateralStabilityProb = 1.0 - (widthRatio - 1.0).abs().clamp(0.0, 0.5) * 2;
    }

    // Combine probabilities
    final sidePlankProbability =
        (alignmentProb * 0.4 + elevationProb * 0.3 + supportStabilityProb * 0.2 + lateralStabilityProb * 0.1);

    return {'up': sidePlankProbability, 'down': 1.0 - sidePlankProbability};
  }

  @override
  Map<String, dynamic> calculateFormMetrics({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
    String? position,
  }) {
    final metrics = <String, double>{};

    try {
      final supportingShoulder = supportingSide == SidePlankSide.left
          ? worldLandmarks[PoseLandmarkType.leftShoulder]
          : worldLandmarks[PoseLandmarkType.rightShoulder];
      final supportingElbow = supportingSide == SidePlankSide.left
          ? worldLandmarks[PoseLandmarkType.leftElbow]
          : worldLandmarks[PoseLandmarkType.rightElbow];
      final supportingWrist = supportingSide == SidePlankSide.left
          ? worldLandmarks[PoseLandmarkType.leftWrist]
          : worldLandmarks[PoseLandmarkType.rightWrist];

      final topShoulder = supportingSide == SidePlankSide.left
          ? worldLandmarks[PoseLandmarkType.rightShoulder]
          : worldLandmarks[PoseLandmarkType.leftShoulder];

      final leftHip = worldLandmarks[PoseLandmarkType.leftHip];
      final rightHip = worldLandmarks[PoseLandmarkType.rightHip];
      final leftAnkle = worldLandmarks[PoseLandmarkType.leftAnkle];
      final rightAnkle = worldLandmarks[PoseLandmarkType.rightAnkle];

      // Body alignment score
      final hipMidpoint = PoseUtilities.getMidpoint(leftHip, rightHip);
      final ankleMidpoint = PoseUtilities.getMidpoint(leftAnkle, rightAnkle);
      final bodyAngle = PoseUtilities.getAngle(supportingShoulder, hipMidpoint, ankleMidpoint);
      final alignmentScore = PoseUtilities.normalize(bodyAngle, 160.0, 180.0);
      metrics['body_alignment'] = alignmentScore;

      // Hip elevation score
      final supportingArmPoint = supportingWrist.visibility > 0.7 ? supportingWrist : supportingElbow;
      final hipElevation = (supportingArmPoint.y - hipMidpoint.y);
      final elevationScore = PoseUtilities.normalize(hipElevation, -0.2, 0.3);
      metrics['hip_elevation'] = elevationScore;

      // Supporting arm stability
      if (supportingWrist.visibility > 0.7) {
        final supportArmAngle = PoseUtilities.getAngle(supportingShoulder, supportingElbow, supportingWrist);
        final armStabilityScore = PoseUtilities.normalize(supportArmAngle, 120.0, 180.0);
        metrics['supporting_arm_stability'] = armStabilityScore;
      } else {
        metrics['supporting_arm_stability'] = 0.5;
      }

      // Note: Arm positioning metrics removed due to sideways camera orientation
      // These measurements are unreliable when user is facing sideways

      // Shoulder stacking (top shoulder should be over bottom shoulder)
      final shoulderStackingDistance = (topShoulder.x - supportingShoulder.x).abs();
      final shoulderStackingScore = 1.0 - PoseUtilities.normalize(shoulderStackingDistance, 0.0, 0.2);
      metrics['shoulder_stacking'] = shoulderStackingScore;

      // Hip stacking (similar to shoulder stacking)
      final hipStackingDistance = (leftHip.x - rightHip.x).abs();
      final ankleStackingDistance = (leftAnkle.x - rightAnkle.x).abs();
      final avgStackingDistance = (hipStackingDistance + ankleStackingDistance) / 2;
      final hipStackingScore = 1.0 - PoseUtilities.normalize(avgStackingDistance, 0.0, 0.15);
      metrics['hip_stacking'] = hipStackingScore;

      // Core stability (combination of alignment and stacking)
      final coreStabilityScore =
          (metrics['body_alignment']! + metrics['shoulder_stacking']! + metrics['hip_stacking']!) / 3;
      metrics['core_stability'] = coreStabilityScore;
    } catch (e) {
      // Fallback values on error
      metrics['body_alignment'] = 0.5;
      metrics['hip_elevation'] = 0.5;
      metrics['supporting_arm_stability'] = 0.5;
      metrics['shoulder_stacking'] = 0.5;
      metrics['hip_stacking'] = 0.5;
      metrics['core_stability'] = 0.5;
    }

    // Add overall visibility
    final visibilityScore = worldLandmarks.map((l) => l.visibility).reduce((a, b) => a + b) / worldLandmarks.length;
    metrics['overall_visibility'] = visibilityScore;

    return _generateFeedbackMessages(formMetrics: metrics);
  }

  Map<String, dynamic> _generateFeedbackMessages({required Map<String, double> formMetrics}) {
    final feedback = <String, dynamic>{};
    final sideText = supportingSide == SidePlankSide.left ? 'left' : 'right';

    // Body alignment feedback
    if (formMetrics['body_alignment'] != null) {
      final alignment = formMetrics['body_alignment']!;
      feedback['body_alignment'] = <String, dynamic>{'score': alignment};
      if (alignment < 0.7) {
        feedback['body_alignment']['message'] =
            'Should maintain a straight line from head to feet - avoid sagging or bending at the waist';
      }
    }

    // Hip elevation feedback
    if (formMetrics['hip_elevation'] != null) {
      final elevation = formMetrics['hip_elevation']!;
      feedback['hip_elevation'] = <String, dynamic>{'score': elevation};
      if (elevation < 0.7) {
        feedback['hip_elevation']['message'] = 'Should lift hips higher to maintain proper side plank position';
      }
    }

    // Supporting arm stability feedback
    if (formMetrics['supporting_arm_stability'] != null) {
      final armStability = formMetrics['supporting_arm_stability']!;
      feedback['supporting_arm_stability'] = <String, dynamic>{'score': armStability};
      if (armStability < 0.7) {
        feedback['supporting_arm_stability']['message'] = 'Should keep the $sideText supporting arm strong and stable';
      }
    }

    // Note: Arm positioning feedback removed due to sideways camera orientation
    // These measurements are unreliable when user is facing sideways

    // Shoulder stacking feedback
    if (formMetrics['shoulder_stacking'] != null) {
      final shoulderStacking = formMetrics['shoulder_stacking']!;
      feedback['shoulder_stacking'] = <String, dynamic>{'score': shoulderStacking};
      if (shoulderStacking < 0.7) {
        feedback['shoulder_stacking']['message'] =
            'Should keep shoulders stacked vertically - avoid rotating or twisting the torso';
      }
    }

    // Hip stacking feedback
    if (formMetrics['hip_stacking'] != null) {
      final hipStacking = formMetrics['hip_stacking']!;
      feedback['hip_stacking'] = <String, dynamic>{'score': hipStacking};
      if (hipStacking < 0.7) {
        feedback['hip_stacking']['message'] = 'Should keep hips and legs stacked to maintain proper side plank form';
      }
    }

    // Core stability feedback
    if (formMetrics['core_stability'] != null) {
      final coreStability = formMetrics['core_stability']!;
      feedback['core_stability'] = <String, dynamic>{'score': coreStability};
      if (coreStability < 0.7) {
        feedback['core_stability']['message'] =
            'Should engage core muscles to maintain stability and prevent body rotation';
      }
    }

    // Overall visibility feedback
    if (formMetrics['overall_visibility'] != null) {
      final visibility = formMetrics['overall_visibility']!;
      feedback['overall_visibility'] = <String, dynamic>{'score': visibility};
      if (visibility < 0.7) {
        feedback['overall_visibility']['message'] = 'Should ensure the whole body is clearly visible in the camera';
      }
    }

    return feedback;
  }
}
