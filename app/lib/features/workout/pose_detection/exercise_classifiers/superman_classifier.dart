part of 'exercise_classifiers.dart';

class SupermanClassifier extends ExerciseClassifier {
  @override
  Map<String, double> _calculateProbabilities({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    final shoulderCenter = PoseUtilities.getMidpoint(
      imageLandmarks[PoseLandmarkType.leftShoulder],
      imageLandmarks[PoseLandmarkType.rightShoulder],
    );
    final hipCenter = PoseUtilities.getMidpoint(
      imageLandmarks[PoseLandmarkType.leftHip],
      imageLandmarks[PoseLandmarkType.rightHip],
    );
    final ankleCenter = PoseUtilities.getMidpoint(
      imageLandmarks[PoseLandmarkType.leftAnkle],
      imageLandmarks[PoseLandmarkType.rightAnkle],
    );

    if (shoulderCenter.visibility < 0.6 || hipCenter.visibility < 0.6) {
      return _neutralResult();
    }

    // --- Improved data-driven Algorithm ---
    // UP state: chest_elev median=0.339, leg_elev median=0.586
    // DOWN state: chest_elev median=0.176, leg_elev median=0.001
    // Leg elevation shows better separation, so weight it more heavily

    final bodyLengthProxy = (Vector2(hipCenter.x, hipCenter.y).distanceTo(Vector2(ankleCenter.x, ankleCenter.y))).abs();
    if (bodyLengthProxy < 0.01) return _neutralResult();

    // Signal 1: Chest Elevation (less reliable due to noise)
    final chestElevation = hipCenter.y - shoulderCenter.y; // Positive when chest is up
    final normalizedChestElevation = chestElevation / bodyLengthProxy;
    // Use robust range that handles outliers better
    final chestUpProb = PoseUtilities.normalize(normalizedChestElevation, -0.2, 0.8);

    // Signal 2: Leg Elevation (more reliable, weight heavily)
    double legUpProb = 0.5; // Neutral if ankles aren't visible
    if (ankleCenter.visibility > 0.6) {
      final legElevation = hipCenter.y - ankleCenter.y; // Positive when legs are up
      final normalizedLegElevation = legElevation / bodyLengthProxy;
      // Use tighter range based on actual data for better discrimination
      // DOWN: median=0.001, UP: median=0.586
      legUpProb = PoseUtilities.normalize(normalizedLegElevation, -0.3, 0.9);
    }

    // Weight leg elevation much more heavily since it's more reliable
    final upProbability = (chestUpProb * 0.2 + legUpProb * 0.8);
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
      final leftShoulder = worldLandmarks[PoseLandmarkType.leftShoulder];
      final rightShoulder = worldLandmarks[PoseLandmarkType.rightShoulder];
      final leftHip = worldLandmarks[PoseLandmarkType.leftHip];
      final rightHip = worldLandmarks[PoseLandmarkType.rightHip];
      final leftWrist = worldLandmarks[PoseLandmarkType.leftWrist];
      final rightWrist = worldLandmarks[PoseLandmarkType.rightWrist];
      final leftAnkle = worldLandmarks[PoseLandmarkType.leftAnkle];
      final rightAnkle = worldLandmarks[PoseLandmarkType.rightAnkle];

      final shoulderMid = PoseUtilities.getMidpoint(leftShoulder, rightShoulder);
      final hipMid = PoseUtilities.getMidpoint(leftHip, rightHip);
      final wristMid = PoseUtilities.getMidpoint(leftWrist, rightWrist);
      final ankleMid = PoseUtilities.getMidpoint(leftAnkle, rightAnkle);

      // Position-aware arm extension
      final armExtensionDistance = sqrt(pow(shoulderMid.x - wristMid.x, 2) + pow(shoulderMid.y - wristMid.y, 2));
      double armExtensionScore;
      if (position == 'up') {
        // In UP position, expect more forward extension
        armExtensionScore = PoseUtilities.normalize(armExtensionDistance, 0.2, 0.6);
      } else if (position == 'down') {
        // In DOWN position, arms may be closer to body
        armExtensionScore = PoseUtilities.normalize(armExtensionDistance, 0.1, 0.5);
      } else {
        // Position-agnostic (fallback)
        armExtensionScore = PoseUtilities.normalize(armExtensionDistance, 0.1, 0.6);
      }
      metrics['arm_extension'] = armExtensionScore;

      // Position-aware leg extension
      final legExtensionDistance = sqrt(pow(hipMid.x - ankleMid.x, 2) + pow(hipMid.y - ankleMid.y, 2));
      double legExtensionScore;
      if (position == 'up') {
        // In UP position, expect significant leg lift
        legExtensionScore = PoseUtilities.normalize(legExtensionDistance, 0.3, 0.8);
      } else if (position == 'down') {
        // In DOWN position, legs may be on ground or minimally lifted
        legExtensionScore = PoseUtilities.normalize(legExtensionDistance, 0.2, 0.6);
      } else {
        // Position-agnostic (fallback)
        legExtensionScore = PoseUtilities.normalize(legExtensionDistance, 0.2, 0.8);
      }
      metrics['leg_extension'] = legExtensionScore;

      // Bilateral symmetry (position-independent)
      final leftArmAngle = PoseUtilities.getAngle(leftShoulder, leftShoulder, leftWrist);
      final rightArmAngle = PoseUtilities.getAngle(rightShoulder, rightShoulder, rightWrist);
      final armSymmetryScore = 1.0 - (leftArmAngle - rightArmAngle).abs() / 45.0;
      metrics['bilateral_symmetry'] = armSymmetryScore.clamp(0.0, 1.0);
    } catch (e) {
      metrics['arm_extension'] = 0.5;
      metrics['leg_extension'] = 0.5;
      metrics['bilateral_symmetry'] = 0.5;
    }

    final visibilityScore = worldLandmarks.map((l) => l.visibility).reduce((a, b) => a + b) / worldLandmarks.length;
    metrics['overall_visibility'] = visibilityScore;

    return _generateFeedbackMessages(formMetrics: metrics, position: position);
  }

  Map<String, dynamic> _generateFeedbackMessages({required Map<String, double> formMetrics, String? position}) {
    final feedback = <String, dynamic>{};

    // Arm extension feedback
    if (formMetrics['arm_extension'] != null) {
      final armExtension = formMetrics['arm_extension']!;
      feedback['arm_extension'] = <String, dynamic>{'score': armExtension};
      if (armExtension < 0.6) {
        // Adjusted threshold based on average: 0.667, set to 0.6
        feedback['arm_extension']['message'] = 'Should extend the arms further forward and lift them higher';
      }
    }

    // Leg extension feedback
    if (formMetrics['leg_extension'] != null) {
      final legExtension = formMetrics['leg_extension']!;
      feedback['leg_extension'] = <String, dynamic>{'score': legExtension};
      if (legExtension < 0.8) {
        // Adjusted threshold based on average: 0.848, set to 0.8
        feedback['leg_extension']['message'] = 'Should lift the legs higher and extend them further back';
      }
    }

    // Bilateral symmetry feedback
    if (formMetrics['bilateral_symmetry'] != null) {
      final symmetry = formMetrics['bilateral_symmetry']!;
      feedback['bilateral_symmetry'] = <String, dynamic>{'score': symmetry};
      if (symmetry < 0.9) {
        // Adjusted threshold based on average: 1.000, set to 0.9 (very high standard)
        feedback['bilateral_symmetry']['message'] = 'Should ensure both arms and legs lift evenly';
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
