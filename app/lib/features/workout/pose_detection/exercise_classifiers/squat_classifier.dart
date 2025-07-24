part of 'exercise_classifiers.dart';

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
