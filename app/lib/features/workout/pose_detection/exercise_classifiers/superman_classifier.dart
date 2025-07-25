part of 'exercise_classifiers.dart';

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
  Map<String, dynamic> calculateFormMetrics({
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

    return _generateFeedbackMessages(formMetrics: metrics);
  }

  Map<String, dynamic> _generateFeedbackMessages({required Map<String, double> formMetrics}) {
    final feedback = <String, dynamic>{};

    // Spinal alignment feedback
    if (formMetrics['spinal_alignment'] != null) {
      final spinalAlignment = formMetrics['spinal_alignment']!;
      feedback['spinal_alignment'] = {'score': spinalAlignment};
      if (spinalAlignment < 0.6) {
        feedback['spinal_alignment']['message'] = 'Should lift the chest higher and extend the back more';
      }
    }

    // Arm extension feedback
    if (formMetrics['arm_extension'] != null) {
      final armExtension = formMetrics['arm_extension']!;
      feedback['arm_extension'] = {'score': armExtension};
      if (armExtension < 0.6) {
        feedback['arm_extension']['message'] = 'Should extend the arms further forward and lift them higher';
      }
    }

    // Leg extension feedback
    if (formMetrics['leg_extension'] != null) {
      final legExtension = formMetrics['leg_extension']!;
      feedback['leg_extension'] = {'score': legExtension};
      if (legExtension < 0.6) {
        feedback['leg_extension']['message'] = 'Should lift the legs higher and extend them further back';
      }
    }

    // Bilateral symmetry feedback
    if (formMetrics['bilateral_symmetry'] != null) {
      final symmetry = formMetrics['bilateral_symmetry']!;
      feedback['bilateral_symmetry'] = {'score': symmetry};
      if (symmetry < 0.6) {
        feedback['bilateral_symmetry']['message'] = 'Should ensure both arms and legs lift evenly';
      }
    }

    // Overall visibility feedback
    if (formMetrics['overall_visibility'] != null) {
      final visibility = formMetrics['overall_visibility']!;
      feedback['overall_visibility'] = {'score': visibility};
      if (visibility < 0.7) {
        feedback['overall_visibility']['message'] = 'Should ensure the whole body is clearly visible in the camera';
      }
    }

    return feedback;
  }
}
