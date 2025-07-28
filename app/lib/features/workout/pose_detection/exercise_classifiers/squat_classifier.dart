part of 'exercise_classifiers.dart';

class SquatClassifier extends ExerciseClassifier {
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
  Map<String, dynamic> calculateFormMetrics({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
    String? position,
  }) {
    final metrics = <String, double>{};

    try {
      final leftKnee = worldLandmarks[PoseLandmarkType.leftKnee];
      final rightKnee = worldLandmarks[PoseLandmarkType.rightKnee];
      final leftHip = worldLandmarks[PoseLandmarkType.leftHip];
      final rightHip = worldLandmarks[PoseLandmarkType.rightHip];

      // Note: Knee tracking metrics removed for regular squats due to sideways camera orientation
      // X-axis measurements like (leftKnee.x - leftAnkle.x) are unreliable when user faces sideways

      // Position-aware depth assessment
      final hipKneeDiff = (leftHip.y + rightHip.y) / 2 - (leftKnee.y + rightKnee.y) / 2;
      double depthScore;
      if (position == 'down') {
        // In DOWN position, depth is critical - expect hips below knees
        depthScore = hipKneeDiff > 0 ? 1.0 : 0.5 + (hipKneeDiff.abs() * 0.5).clamp(0.0, 0.5);
      } else if (position == 'up') {
        // In UP position, being above knee level is expected and acceptable
        depthScore = hipKneeDiff < 0 ? 1.0 : 0.8 - (hipKneeDiff * 0.3).clamp(0.0, 0.3);
      } else {
        // Position-agnostic (fallback)
        depthScore = hipKneeDiff > 0 ? 1.0 : 0.7 + (hipKneeDiff.abs() * 0.3).clamp(0.0, 0.3);
      }
      metrics['squat_depth'] = depthScore;

      // Note: Stance width metrics removed for regular squats due to sideways camera orientation
      // These measurements are unreliable when user is facing sideways
    } catch (e) {
      // Fallback values on error
      metrics['squat_depth'] = 0.5;
    }

    // Add overall visibility
    final visibilityScore = worldLandmarks.map((l) => l.visibility).reduce((a, b) => a + b) / worldLandmarks.length;
    metrics['overall_visibility'] = visibilityScore;

    return _generateFeedbackMessages(formMetrics: metrics, position: position);
  }

  Map<String, dynamic> _generateFeedbackMessages({required Map<String, double> formMetrics, String? position}) {
    final feedback = <String, dynamic>{};

    // Note: Knee tracking feedback removed for regular squats due to sideways camera orientation
    // These measurements are unreliable when user is facing sideways

    // Squat depth feedback
    if (formMetrics['squat_depth'] != null) {
      final depth = formMetrics['squat_depth']!;
      feedback['squat_depth'] = <String, dynamic>{'score': depth};
      if (depth < 0.5) {
        // Lowered threshold from 0.7 to 0.5
        feedback['squat_depth']['message'] =
            'Should squat deeper, lowering the hips below knee level for a full range of motion';
      }
    }

    // Note: Stance width feedback removed for regular squats due to sideways camera orientation
    // These measurements are unreliable when user is facing sideways

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

class SumoSquatClassifier extends ExerciseClassifier {
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
  Map<String, dynamic> calculateFormMetrics({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
    String? position,
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
      // Reduced sensitivity: was * 10, now * 5
      final avgKneeTrackingScore = 1.0 - ((leftKneeAnkleDistance + rightKneeAnkleDistance) / 2 * 5).clamp(0.0, 1.0);
      metrics['knee_tracking'] = avgKneeTrackingScore;

      // Depth
      final hipKneeDiff = (leftHip.y + rightHip.y) / 2 - (leftKnee.y + rightKnee.y) / 2;
      // More gradual scoring instead of binary
      final depthScore = hipKneeDiff > 0 ? 1.0 : 0.7 + (hipKneeDiff.abs() * 0.3).clamp(0.0, 0.3);
      metrics['squat_depth'] = depthScore;
    } catch (e) {
      metrics['knee_tracking'] = 0.5;
      metrics['squat_depth'] = 0.5;
    }

    final visibilityScore = worldLandmarks.map((l) => l.visibility).reduce((a, b) => a + b) / worldLandmarks.length;
    metrics['overall_visibility'] = visibilityScore;

    return _generateFeedbackMessages(formMetrics: metrics, position: position);
  }

  Map<String, dynamic> _generateFeedbackMessages({required Map<String, double> formMetrics, String? position}) {
    final feedback = <String, dynamic>{};

    // Knee tracking feedback
    if (formMetrics['knee_tracking'] != null) {
      final kneeTracking = formMetrics['knee_tracking']!;
      feedback['knee_tracking'] = <String, dynamic>{'score': kneeTracking};
      if (kneeTracking < 0.4) {
        // Lowered threshold from 0.6 to 0.4
        feedback['knee_tracking']['message'] =
            'Should keep both knees aligned over the toes and avoid letting them cave inward';
      }
    }

    // Squat depth feedback
    if (formMetrics['squat_depth'] != null) {
      final depth = formMetrics['squat_depth']!;
      feedback['squat_depth'] = <String, dynamic>{'score': depth};
      if (depth < 0.5) {
        // Lowered threshold from 0.7 to 0.5
        feedback['squat_depth']['message'] =
            'Should squat deeper, lowering the hips below knee level for a full range of motion';
      }
    }

    // Overall visibility feedback
    if (formMetrics['overall_visibility'] != null) {
      final visibility = formMetrics['overall_visibility']!;
      feedback['overall_visibility'] = <String, dynamic>{'score': visibility};
      if (visibility < 0.7) {
        feedback['overall_visibility'] = {'message': 'Should ensure the whole body is clearly visible in the camera'};
      }
    }

    return feedback;
  }
}

enum SplitSquatSide { left, right }

class SplitSquatClassifier extends ExerciseClassifier {
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
  Map<String, dynamic> calculateFormMetrics({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
    String? position,
  }) {
    final metrics = <String, double>{};

    try {
      final frontHipIdx = frontLeg == SplitSquatSide.left ? PoseLandmarkType.leftHip : PoseLandmarkType.rightHip;
      final frontKneeIdx = frontLeg == SplitSquatSide.left ? PoseLandmarkType.leftKnee : PoseLandmarkType.rightKnee;
      final frontAnkleIdx = frontLeg == SplitSquatSide.left ? PoseLandmarkType.leftAnkle : PoseLandmarkType.rightAnkle;

      final frontHip = worldLandmarks[frontHipIdx];
      final frontKnee = worldLandmarks[frontKneeIdx];
      final frontAnkle = worldLandmarks[frontAnkleIdx];

      // Front knee tracking using angle-based algorithm
      if (position == 'down') {
        // Down position: use front knee angle, target ~90°
        final frontKneeAngle = PoseUtilities.getAngle(frontHip, frontKnee, frontAnkle);
        final deviationFromTarget = (frontKneeAngle - 90.0).abs();
        // Score based on how close to 90° (allow ±15° tolerance)
        final kneeTrackingScore = 1.0 - (deviationFromTarget / 30.0).clamp(0.0, 1.0);
        metrics['front_knee_tracking'] = kneeTrackingScore;
      } else if (position == 'up') {
        // Up position: use left ankle, hip, right ankle angle, target ~60°
        final leftAnkle = worldLandmarks[PoseLandmarkType.leftAnkle];
        final rightAnkle = worldLandmarks[PoseLandmarkType.rightAnkle];
        final hip = worldLandmarks[PoseLandmarkType.leftHip]; // Use left hip as reference

        final ankleHipAnkleAngle = PoseUtilities.getAngle(leftAnkle, hip, rightAnkle);
        final deviationFromTarget = (ankleHipAnkleAngle - 60.0).abs();
        // Score based on how close to 60° (allow ±20° tolerance)
        final kneeTrackingScore = 1.0 - (deviationFromTarget / 40.0).clamp(0.0, 1.0);
        metrics['front_knee_tracking'] = kneeTrackingScore;
      } else {
        // Position-agnostic (fallback): use front knee angle
        final frontKneeAngle = PoseUtilities.getAngle(frontHip, frontKnee, frontAnkle);
        final deviationFromTarget = (frontKneeAngle - 120.0).abs(); // Mid-range target
        final kneeTrackingScore = 1.0 - (deviationFromTarget / 60.0).clamp(0.0, 1.0);
        metrics['front_knee_tracking'] = kneeTrackingScore;
      }
    } catch (e) {
      metrics['front_knee_tracking'] = 0.5;
    }

    final visibilityScore = worldLandmarks.map((l) => l.visibility).reduce((a, b) => a + b) / worldLandmarks.length;
    metrics['overall_visibility'] = visibilityScore;

    return _generateFeedbackMessages(formMetrics: metrics, position: position);
  }

  Map<String, dynamic> _generateFeedbackMessages({required Map<String, double> formMetrics, String? position}) {
    final feedback = <String, dynamic>{};

    // Front knee tracking feedback
    if (formMetrics['front_knee_tracking'] != null) {
      final kneeTracking = formMetrics['front_knee_tracking']!;
      feedback['front_knee_tracking'] = <String, dynamic>{'score': kneeTracking};
      if (kneeTracking < 0.6) {
        if (position == 'down') {
          feedback['front_knee_tracking']['message'] =
              'Should aim for approximately 90° front knee angle in the down position';
        } else if (position == 'up') {
          feedback['front_knee_tracking']['message'] =
              'Should maintain proper leg positioning with approximately 60° angle between ankles and hip in the up position';
        } else {
          feedback['front_knee_tracking']['message'] =
              'Should maintain proper front knee alignment throughout the movement';
        }
      }
    }

    // Overall visibility feedback
    if (formMetrics['overall_visibility'] != null) {
      final visibility = formMetrics['overall_visibility']!;
      feedback['overall_visibility'] = <String, dynamic>{'score': visibility};
      if (visibility < 0.7) {
        feedback['overall_visibility'] = {'message': 'Should ensure the whole body is clearly visible in the camera'};
      }
    }

    return feedback;
  }
}
