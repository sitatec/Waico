part of 'exercise_classifiers.dart';

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
