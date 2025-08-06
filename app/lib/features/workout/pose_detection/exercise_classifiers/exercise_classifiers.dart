import 'dart:collection';
import 'dart:math';
import 'package:waico/features/workout/pose_detection/exercise_classifiers/utils.dart';
import 'package:waico/features/workout/pose_detection/pose_models.dart';
import 'package:vector_math/vector_math_64.dart';

part 'pushup_classifier.dart';
part 'squat_classifier.dart';
part 'crunch_classifier.dart';
part 'superman_classifier.dart';
part 'plank_classifier.dart';

abstract class ExerciseClassifier {
  final int smoothingWindow;
  final Queue<Map<String, double>> _history = Queue();

  ExerciseClassifier({this.smoothingWindow = 5});

  bool get isDurationBased => false;

  Map<String, dynamic> classify({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    final rawProbabilities = _calculateProbabilities(worldLandmarks: worldLandmarks, imageLandmarks: imageLandmarks);
    // Extract only the probability values for smoothing
    final probabilitiesOnly = <String, double>{
      'up': (rawProbabilities['up'] as num?)?.toDouble() ?? 0.5,
      'down': (rawProbabilities['down'] as num?)?.toDouble() ?? 0.5,
    };
    _history.add(probabilitiesOnly);
    if (_history.length > smoothingWindow) {
      _history.removeFirst();
    }

    final smoothedProbabilities = _getSmoothedProbabilities();
    final result = <String, dynamic>{'up': smoothedProbabilities['up'], 'down': smoothedProbabilities['down']};

    // Include feedback if present in raw probabilities
    if (rawProbabilities.containsKey('feedback')) {
      result['feedback'] = rawProbabilities['feedback'];
    }

    return result;
  }

  Map<String, dynamic> _calculateProbabilities({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  });

  /// Calculate exercise-specific form metrics
  /// Returns a map of metric names to scores (0.0 - 1.0)
  /// [position] indicates the current exercise position ('up', 'down', or null for position-agnostic)
  Map<String, dynamic> calculateFormMetrics({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
    String? position,
  }) {
    // Default implementation returns overall visibility
    final visibilityScore = worldLandmarks.map((l) => l.visibility).reduce((a, b) => a + b) / worldLandmarks.length;
    return {
      'overall_visibility': {'score': visibilityScore},
    };
  }

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

  Map<String, dynamic> _neutralResult() => {'up': 0.5, 'down': 0.5};
}
