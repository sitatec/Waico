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

    // --- Data-driven Algorithm based on actual measurements ---
    // Knee Pushup UP: median elbow=157.8°, range=134.6°-179.0°
    // Knee Pushup DOWN: median elbow=83.9°, range=48.4°-149.8°
    // Key insight: There's overlap between 134.6°-149.8°, use more precise ranges

    // Signal 1: Elbow Angle (Primary, heavily weighted)
    final elbowAngle = PoseUtilities.getAngle(shoulder3D, elbow3D, wrist3D);

    // Use tighter normalization that better separates the states
    // Focus on the non-overlapping regions for better discrimination
    double angleProb;
    if (elbowAngle >= 150.0) {
      // Clearly in UP range
      angleProb = 1.0;
    } else if (elbowAngle <= 120.0) {
      // Clearly in DOWN range
      angleProb = 0.0;
    } else {
      // Overlap region (120°-150°) - use linear interpolation but be conservative
      angleProb = (elbowAngle - 120.0) / (150.0 - 120.0);
      // Apply sigmoid-like function to make the transition less linear
      angleProb = angleProb * angleProb; // Square to push toward extremes
    }

    // Signal 2: Shoulder Height relative to Wrist (Secondary, but inverted!)
    // Analysis shows DOWN state has HIGHER shoulder heights (counter-intuitive)
    // DOWN: median=3.796, UP: median=2.350
    final shoulderHeight = PoseUtilities.getVerticalDistance(shoulder2D, wrist2D);
    final torsoHeight = PoseUtilities.getVerticalDistance(shoulder2D, hip2D);

    if (torsoHeight < 0.01) return _neutralResult();

    final normalizedShoulderHeight = shoulderHeight / torsoHeight;
    // Invert the height signal: higher height = more likely DOWN position
    final heightProb = 1.0 - PoseUtilities.normalize(normalizedShoulderHeight, 1.5, 6.0);

    // Weight angle much more heavily since it's more reliable
    final upProbability = (angleProb * 0.9 + heightProb * 0.1);
    return {'up': upProbability, 'down': 1.0 - upProbability};
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
}

class SumoSquatClassifier extends PoseClassifier {
  // Sumo Squat logic is similar to a regular squat but averages both legs.
  // The enhanced logic from SquatClassifier is directly applicable and beneficial here.
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

    // Signal 1: Average Knee Angle
    final lKneeAngle = PoseUtilities.getAngle(lHip, lKnee, lAnkle);
    final rKneeAngle = PoseUtilities.getAngle(rHip, rKnee, rAnkle);
    final avgKneeAngle = (lKneeAngle + rKneeAngle) / 2.0;
    final angleProb = PoseUtilities.normalize(avgKneeAngle, 95.0, 170.0);

    // Signal 2: Average Hip Height
    final lHip2D = imageLandmarks[PoseLandmarkType.leftHip];
    final lKnee2D = imageLandmarks[PoseLandmarkType.leftKnee];
    final lAnkle2D = imageLandmarks[PoseLandmarkType.leftAnkle];
    final rHip2D = imageLandmarks[PoseLandmarkType.rightHip];
    final rKnee2D = imageLandmarks[PoseLandmarkType.rightKnee];
    final rAnkle2D = imageLandmarks[PoseLandmarkType.rightAnkle];

    final lHipKneeDiff = lKnee2D.y - lHip2D.y;
    final rHipKneeDiff = rKnee2D.y - rHip2D.y;
    final avgHipKneeDiff = (lHipKneeDiff + rHipKneeDiff) / 2.0;

    final lShinHeight = PoseUtilities.getVerticalDistance(lKnee2D, lAnkle2D);
    final rShinHeight = PoseUtilities.getVerticalDistance(rKnee2D, rAnkle2D);
    final avgShinHeight = (lShinHeight + rShinHeight) / 2.0;
    if (avgShinHeight < 0.01) return _neutralResult();

    final normalizedHipHeight = avgHipKneeDiff / avgShinHeight;
    final heightProb = PoseUtilities.normalize(normalizedHipHeight, 0.0, 1.0);

    final upProbability = (angleProb * 0.5 + heightProb * 0.5);
    return {'up': upProbability, 'down': 1.0 - upProbability};
  }
}

enum SplitSquatSide { left, right }

class SplitSquatClassifier extends PoseClassifier {
  final SplitSquatSide frontLeg;

  SplitSquatClassifier({required this.frontLeg, int smoothingWindow = 5}) : super(smoothingWindow: smoothingWindow);

  @override
  Map<String, double> _calculateProbabilities({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    // Determine the landmark indices for the designated front leg.
    final hipIdx = frontLeg == SplitSquatSide.left ? PoseLandmarkType.leftHip : PoseLandmarkType.rightHip;
    final kneeIdx = frontLeg == SplitSquatSide.left ? PoseLandmarkType.leftKnee : PoseLandmarkType.rightKnee;
    final ankleIdx = frontLeg == SplitSquatSide.left ? PoseLandmarkType.leftAnkle : PoseLandmarkType.rightAnkle;

    // Get the required landmarks using both world and image coordinates.
    final hip3D = worldLandmarks[hipIdx];
    final knee3D = worldLandmarks[kneeIdx];
    final ankle3D = worldLandmarks[ankleIdx];

    final hip2D = imageLandmarks[hipIdx];
    final knee2D = imageLandmarks[kneeIdx];
    final ankle2D = imageLandmarks[ankleIdx];

    // Ensure the key landmarks for the front leg are clearly visible.
    if (hip3D.visibility < 0.8 || knee3D.visibility < 0.8 || ankle3D.visibility < 0.8) {
      return _neutralResult();
    }

    // --- Granular Algorithm ---
    // The logic mirrors the standard SquatClassifier but is applied only to the front leg.
    // 1. Front Knee Angle (Primary): The angle of the front leg's knee joint.
    // 2. Front Hip Height (Secondary): The vertical position of the front hip relative to the front knee.

    // Signal 1: Knee Angle
    // Measures the bend in the primary working leg.
    final kneeAngle = PoseUtilities.getAngle(hip3D, knee3D, ankle3D);
    // In a deep split squat, the knee angle is around 90°. When up, it's nearly straight.
    final angleProb = PoseUtilities.normalize(kneeAngle, 90.0, 170.0);

    // Signal 2: Hip Height over Knee
    // Measures how far the user has lowered their body.
    final hipKneeHeightDiff = knee2D.y - hip2D.y; // Positive when hip is above knee

    // Normalize by the front leg's shin height for scale-invariance.
    final shinHeight = PoseUtilities.getVerticalDistance(knee2D, ankle2D);
    if (shinHeight < 0.01) return _neutralResult(); // Avoid division by zero

    final normalizedHipHeight = hipKneeHeightDiff / shinHeight;
    // Down: hip is near the knee (ratio ~0.0-0.2). Up: hip is high above knee (ratio ~1.0-1.1).
    final heightProb = PoseUtilities.normalize(normalizedHipHeight, 0.1, 1.1);

    // Combine probabilities with a weighted average for a robust result.
    final upProbability = (angleProb * 0.6 + heightProb * 0.4);

    return {'up': upProbability, 'down': 1.0 - upProbability};
  }
}

// -------------------- CRUNCH FAMILY --------------------

class CrunchClassifier extends PoseClassifier {
  @override
  Map<String, double> _calculateProbabilities({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
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

    if (shoulderCenter3D.visibility < 0.7 || hipCenter3D.visibility < 0.7) {
      return _neutralResult();
    }

    // --- Data-driven Algorithm based on actual measurements ---
    // UP state: torso_angle median=117.9°, shoulder_elev median=0.639
    // DOWN state: torso_angle median=130.7°, shoulder_elev median=0.117

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
}

class ReverseCrunchClassifier extends PoseClassifier {
  @override
  Map<String, double> _calculateProbabilities({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
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

    final hipCenter2D = PoseUtilities.getMidpoint(
      imageLandmarks[PoseLandmarkType.leftHip],
      imageLandmarks[PoseLandmarkType.rightHip],
    );
    final kneeCenter2D = PoseUtilities.getMidpoint(
      imageLandmarks[PoseLandmarkType.leftKnee],
      imageLandmarks[PoseLandmarkType.rightKnee],
    );

    if (hipCenter3D.visibility < 0.7 || kneeCenter3D.visibility < 0.7) return _neutralResult();

    // --- Data-driven Algorithm based on comprehensive crunch analysis ---
    // UP (reverse_crunch_up): hip-knee angle median=61.7°, knee elevation median=0.218
    // DOWN (crunch_down): hip-knee angle median=130.7°, knee elevation median=0.343
    // UP has SMALLER angles (more flexed) and SMALLER knee elevation

    // Signal 1: Hip Flexion Angle (Primary)
    final hipFlexionAngle = PoseUtilities.getAngle(shoulderCenter3D, hipCenter3D, kneeCenter3D);
    // DOWN: ~130.7°, UP: ~61.7° - smaller angle means more flexed (up)
    final angleProb = 1.0 - PoseUtilities.normalize(hipFlexionAngle, 30.0, 170.0);

    // Signal 2: Knee Elevation (Secondary)
    final kneeElevation = PoseUtilities.getVerticalDistance(hipCenter2D, kneeCenter2D);
    // DOWN: ~0.343, UP: ~0.218 - surprisingly, UP has lower knee elevation
    // This makes sense as in reverse crunch, knees come toward chest (lower relative position)
    final elevationProb = 1.0 - PoseUtilities.normalize(kneeElevation, 0.05, 0.52);

    final upProbability = (angleProb * 0.7 + elevationProb * 0.3);
    return {'up': upProbability, 'down': 1.0 - upProbability};
  }
}

class DoubleCrunchClassifier extends PoseClassifier {
  @override
  Map<String, double> _calculateProbabilities({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
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
    final kneeCenter2D = PoseUtilities.getMidpoint(
      imageLandmarks[PoseLandmarkType.leftKnee],
      imageLandmarks[PoseLandmarkType.rightKnee],
    );

    if (shoulderCenter3D.visibility < 0.7 || kneeCenter3D.visibility < 0.7) return _neutralResult();

    // --- Data-driven Algorithm based on comprehensive crunch analysis ---
    // UP (double_crunch_up): shoulder-knee distance median=0.246, torso angle median=71.4°
    // DOWN (crunch_down): shoulder-knee distance median=0.560, torso angle median=130.7°
    // UP has SMALLER distances and SMALLER angles (more crunched)

    // Signal 1: Shoulder-Knee Distance (Primary)
    final shoulderKneeDistance = Vector2(
      shoulderCenter2D.x,
      shoulderCenter2D.y,
    ).distanceTo(Vector2(kneeCenter2D.x, kneeCenter2D.y));

    // Signal 2: Torso Angle (Secondary)
    final torsoAngle = PoseUtilities.getAngle(shoulderCenter3D, hipCenter3D, kneeCenter3D);

    // DOWN: larger distance (~0.56), UP: smaller distance (~0.25)
    // Invert normalization since UP has smaller values
    final distanceProb = 1.0 - PoseUtilities.normalize(shoulderKneeDistance, 0.15, 0.67);

    // DOWN: larger angle (~130.7°), UP: smaller angle (~71.4°)
    // Invert normalization since UP has smaller values
    final angleProb = 1.0 - PoseUtilities.normalize(torsoAngle, 30.0, 170.0);

    // Combine with emphasis on distance as it shows better separation
    final upProbability = (distanceProb * 0.7 + angleProb * 0.3);
    return {'up': upProbability, 'down': 1.0 - upProbability};
  }
}

// -------------------- SUPERMAN FAMILY --------------------

class SupermanClassifier extends PoseClassifier {
  // Covers Superman, Y Superman, and Superman Pulse up/down states.
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
}
