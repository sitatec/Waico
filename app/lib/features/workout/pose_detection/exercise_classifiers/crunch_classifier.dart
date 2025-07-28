part of 'exercise_classifiers.dart';

List<int> _getRequiredLandmark(bool isLeftVisible) {
  if (isLeftVisible) {
    return [
      PoseLandmarkType.nose,
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.leftKnee,
      PoseLandmarkType.leftAnkle,
      PoseLandmarkType.leftWrist,
      PoseLandmarkType.leftElbow,
    ];
  } else {
    return [
      PoseLandmarkType.nose,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.rightHip,
      PoseLandmarkType.rightKnee,
      PoseLandmarkType.rightAnkle,
      PoseLandmarkType.rightWrist,
      PoseLandmarkType.rightElbow,
    ];
  }
}

class CrunchClassifier extends ExerciseClassifier {
  @override
  Map<String, double> _calculateProbabilities({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    final isLeftVisible = PoseUtilities.isLeftBodyVisible(worldLandmarks);

    if (_getRequiredLandmark(isLeftVisible).any((type) => worldLandmarks[type].visibility < 0.65)) {
      return _neutralResult();
    }

    final leftKnee = worldLandmarks[PoseLandmarkType.leftKnee];
    final rightKnee = worldLandmarks[PoseLandmarkType.rightKnee];
    final leftAnkle = worldLandmarks[PoseLandmarkType.leftAnkle];
    final rightAnkle = worldLandmarks[PoseLandmarkType.rightAnkle];
    final leftHip = worldLandmarks[PoseLandmarkType.leftHip];
    final rightHip = worldLandmarks[PoseLandmarkType.rightHip];
    final hipMid = PoseUtilities.getMidpoint(leftHip, rightHip);

    final kneeMid = PoseUtilities.getMidpoint(leftKnee, rightKnee);
    final ankleMid = PoseUtilities.getMidpoint(leftAnkle, rightAnkle);
    // Calculate knee flexion angle
    final kneeAngle = PoseUtilities.getAngle(hipMid, kneeMid, ankleMid);
    // Knees should be bent, no specific angle, but they should not be fully extended
    // We will score knee angle in the metrics instead, here it's just to make sure the user is doing the right exercise
    if (kneeAngle > 160.0) {
      return _neutralResult();
    }

    final shoulderCenter3D = PoseUtilities.getMidpoint(
      worldLandmarks[PoseLandmarkType.leftShoulder],
      worldLandmarks[PoseLandmarkType.rightShoulder],
    );
    final hipCenter3D = PoseUtilities.getMidpoint(
      worldLandmarks[PoseLandmarkType.leftHip],
      worldLandmarks[PoseLandmarkType.rightHip],
    );
    final kneeCenter3D = PoseUtilities.getMidpoint(
      worldLandmarks[PoseLandmarkType.leftKnee],
      worldLandmarks[PoseLandmarkType.rightKnee],
    );

    final shoulderCenter2D = PoseUtilities.getMidpoint(
      imageLandmarks[PoseLandmarkType.leftShoulder],
      imageLandmarks[PoseLandmarkType.rightShoulder],
    );
    final hipCenter2D = PoseUtilities.getMidpoint(
      imageLandmarks[PoseLandmarkType.leftHip],
      imageLandmarks[PoseLandmarkType.rightHip],
    );

    // Signal 1: Torso Angle (Primary)
    final torsoAngle = PoseUtilities.getAngle(shoulderCenter3D, hipCenter3D, kneeCenter3D);
    // UP: ~117.9°, DOWN: ~130.7° - smaller angle means more crunched (up)
    final angleProb = 1.0 - PoseUtilities.normalize(torsoAngle, 110.0, 140.0);

    // Signal 2: Shoulder Elevation (Secondary)
    final shoulderElevation = PoseUtilities.getVerticalDistance(hipCenter2D, shoulderCenter2D);
    final torsoLength = Vector2(
      shoulderCenter2D.x,
      shoulderCenter2D.y,
    ).distanceTo(Vector2(hipCenter2D.x, hipCenter2D.y));
    if (torsoLength < 0.01) return _neutralResult();

    final normalizedElevation = shoulderElevation / torsoLength;
    // DOWN: ~0.117, UP: ~0.639 - higher elevation means more crunched (up)
    final elevationProb = PoseUtilities.normalize(normalizedElevation, 0.05, 0.8);

    // Combine with emphasis on both signals
    final upProbability = (angleProb * 0.6 + elevationProb * 0.4);
    return {'up': upProbability, 'down': 1.0 - upProbability};
  }

  @override
  Map<String, dynamic> calculateFormMetrics({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
    String? position,
  }) {
    final metrics = <String, double>{};

    try {
      final leftHip = worldLandmarks[PoseLandmarkType.leftHip];
      final rightHip = worldLandmarks[PoseLandmarkType.rightHip];
      final leftKnee = worldLandmarks[PoseLandmarkType.leftKnee];
      final rightKnee = worldLandmarks[PoseLandmarkType.rightKnee];

      // Knee stability (position-independent - should always be stable)
      final leftKneeAngle = PoseUtilities.getAngle(leftHip, leftKnee, worldLandmarks[PoseLandmarkType.leftAnkle]);
      final rightKneeAngle = PoseUtilities.getAngle(rightHip, rightKnee, worldLandmarks[PoseLandmarkType.rightAnkle]);
      final avgKneeAngle = (leftKneeAngle + rightKneeAngle) / 2;
      final kneeStabilityScore = 1.0 - (avgKneeAngle - 105.0).abs() / 60.0;
      metrics['knee_stability'] = kneeStabilityScore.clamp(0.0, 1.0);

      // Hip stability (hips should remain relatively level) - position-independent
      final hipLevelDiff = (leftHip.y - rightHip.y).abs();
      final hipStabilityScore = 1.0 - (hipLevelDiff * 10).clamp(0.0, 1.0);
      metrics['hip_stability'] = hipStabilityScore;
    } catch (e) {
      metrics['knee_stability'] = 0.5;
      metrics['hip_stability'] = 0.5;
    }

    final requiredLandmarks = _getRequiredLandmark(PoseUtilities.isLeftBodyVisible(worldLandmarks));
    final visibilityScore =
        requiredLandmarks.map((index) => worldLandmarks[index].visibility).reduce((a, b) => a + b) /
        requiredLandmarks.length;
    metrics['overall_visibility'] = visibilityScore;

    return _generateFeedbackMessages(formMetrics: metrics, position: position);
  }

  Map<String, dynamic> _generateFeedbackMessages({required Map<String, double> formMetrics, String? position}) {
    final feedback = <String, dynamic>{};

    // Knee stability feedback
    if (formMetrics['knee_stability'] != null) {
      final kneeStability = formMetrics['knee_stability']!;
      feedback['knee_stability'] = <String, dynamic>{'score': kneeStability};
      if (kneeStability < 0.3) {
        // Adjusted threshold based on average: 0.358, set to 0.3
        feedback['knee_stability']['message'] =
            'Should keep the knees bent at about 90 degrees and stable throughout the movement';
      }
    }

    // Hip stability feedback
    if (formMetrics['hip_stability'] != null) {
      final hipStability = formMetrics['hip_stability']!;
      feedback['hip_stability'] = <String, dynamic>{'score': hipStability};
      if (hipStability < 0.4) {
        // Adjusted threshold based on average: 0.469, set to 0.4
        feedback['hip_stability']['message'] = 'Should keep the hips level and avoid lifting them';
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

class ReverseCrunchClassifier extends ExerciseClassifier {
  @override
  Map<String, double> _calculateProbabilities({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    final isLeftVisible = PoseUtilities.isLeftBodyVisible(worldLandmarks);

    if (_getRequiredLandmark(isLeftVisible).any((type) => worldLandmarks[type].visibility < 0.65)) {
      return _neutralResult();
    }
    final leftHip = worldLandmarks[PoseLandmarkType.leftHip];
    final rightHip = worldLandmarks[PoseLandmarkType.rightHip];
    final leftKnee = worldLandmarks[PoseLandmarkType.leftKnee];
    final rightKnee = worldLandmarks[PoseLandmarkType.rightKnee];
    final leftShoulder = worldLandmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = worldLandmarks[PoseLandmarkType.rightShoulder];

    // Focus on hip-knee movement relative to torso
    final hipMid = PoseUtilities.getMidpoint(leftHip, rightHip);
    final kneeMid = PoseUtilities.getMidpoint(leftKnee, rightKnee);
    final shoulderMid = PoseUtilities.getMidpoint(leftShoulder, rightShoulder);

    // Hip flexion angle
    final hipFlexionAngle = PoseUtilities.getAngle(shoulderMid, hipMid, kneeMid);

    // In reverse crunch, knees move toward chest
    // DOWN (extended): >~90°, UP (knees to chest): ~60-90°
    final downProb = PoseUtilities.normalize(hipFlexionAngle, 60.0, 120.0);

    return {'up': 1 - downProb, 'down': downProb};
  }

  @override
  Map<String, dynamic> calculateFormMetrics({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
    String? position,
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

      // Range of motion (knees should reach toward chest)
      final hipMid = PoseUtilities.getMidpoint(leftHip, rightHip);
      final kneeMid = PoseUtilities.getMidpoint(leftKnee, rightKnee);
      final shoulderMid = PoseUtilities.getMidpoint(leftShoulder, rightShoulder);
      final romAngle = PoseUtilities.getAngle(shoulderMid, hipMid, kneeMid);
      final romScore = 1.0 - PoseUtilities.normalize(romAngle, 60.0, 180.0);
      metrics['range_of_motion'] = romScore;
    } catch (e) {
      metrics['knee_symmetry'] = 0.5;
      metrics['range_of_motion'] = 0.5;
    }

    final visibilityScore = worldLandmarks.map((l) => l.visibility).reduce((a, b) => a + b) / worldLandmarks.length;
    metrics['overall_visibility'] = visibilityScore;

    return _generateFeedbackMessages(formMetrics: metrics);
  }

  Map<String, dynamic> _generateFeedbackMessages({required Map<String, double> formMetrics}) {
    final feedback = <String, dynamic>{};

    // Knee symmetry feedback
    if (formMetrics['knee_symmetry'] != null) {
      final kneeSymmetry = formMetrics['knee_symmetry']!;
      feedback['knee_symmetry'] = <String, dynamic>{'score': kneeSymmetry};
      if (kneeSymmetry < 0.65) {
        feedback['knee_symmetry']['message'] = 'Should move both knees together, keeping them aligned';
      }
    }

    // Range of motion feedback
    if (formMetrics['range_of_motion'] != null) {
      final rom = formMetrics['range_of_motion']!;
      feedback['range_of_motion'] = <String, dynamic>{'score': rom};
      if (rom < 0.65) {
        feedback['range_of_motion']['message'] =
            'Should bring the knees closer to the chest for a fuller range of motion';
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

class DoubleCrunchClassifier extends ExerciseClassifier {
  @override
  Map<String, double> _calculateProbabilities({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    final isLeftVisible = PoseUtilities.isLeftBodyVisible(worldLandmarks);
    if (_getRequiredLandmark(isLeftVisible).any((type) => worldLandmarks[type].visibility < 0.65)) {
      return _neutralResult();
    }
    // Combines both regular crunch (torso flexion) and reverse crunch (hip flexion)
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

    // Torso flexion (like regular crunch)
    final torsoAngle = PoseUtilities.getAngle(nose, shoulderMid, hipMid);
    final torsoFlexion = 1.0 - PoseUtilities.normalize(torsoAngle, 120.0, 180.0);

    // Hip flexion (like reverse crunch)
    final hipAngle = PoseUtilities.getAngle(shoulderMid, hipMid, kneeMid);
    final hipFlexion = 1.0 - PoseUtilities.normalize(hipAngle, 60.0, 120.0);

    // Both should happen together for double crunch
    final combinedFlexion = (torsoFlexion + hipFlexion) / 2;

    return {'up': combinedFlexion, 'down': 1 - combinedFlexion};
  }

  @override
  Map<String, dynamic> calculateFormMetrics({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
    String? position,
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
      final hipFlexion = 1.0 - PoseUtilities.normalize(hipAngle, 60.0, 120.0);
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

    return _generateFeedbackMessages(formMetrics: metrics);
  }

  Map<String, dynamic> _generateFeedbackMessages({required Map<String, double> formMetrics}) {
    final feedback = <String, dynamic>{};

    // Movement coordination feedback
    if (formMetrics['movement_coordination'] != null) {
      final coordination = formMetrics['movement_coordination']!;
      feedback['movement_coordination'] = <String, dynamic>{'score': coordination};
      if (coordination < 0.5) {
        feedback['movement_coordination']['message'] =
            'Should coordinate both the upper body crunch and knee-to-chest movement simultaneously';
      }
    }

    // Bilateral symmetry feedback
    if (formMetrics['bilateral_symmetry'] != null) {
      final symmetry = formMetrics['bilateral_symmetry']!;
      feedback['bilateral_symmetry'] = <String, dynamic>{'score': symmetry};
      if (symmetry < 0.5) {
        feedback['bilateral_symmetry']['message'] = 'Should ensure both sides of the body move evenly';
      }
    }

    // Full range activation feedback
    if (formMetrics['full_range_activation'] != null) {
      final activation = formMetrics['full_range_activation']!;
      feedback['full_range_activation'] = <String, dynamic>{'score': activation};
      if (activation < 0.4) {
        feedback['full_range_activation']['message'] =
            'Should engage both upper and lower abdominals for maximum muscle activation';
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
