import 'dart:async';
import 'dart:math';
import 'package:waico/features/workout/pose_detection/exercise_classifiers/exercise_classifiers.dart';
import 'package:waico/features/workout/pose_detection/pose_models.dart';

/// Configuration for rep counting parameters
class RepCountingConfig {
  final double probabilityThreshold;
  final int stateStabilityFrames;
  final int minRepInterval;
  final double transitionSensitivity;
  final double qualityThreshold;
  final int maxHistorySize;

  const RepCountingConfig({
    this.probabilityThreshold = 0.65,
    this.stateStabilityFrames = 3,
    this.minRepInterval = 800,
    this.transitionSensitivity = 0.15,
    this.qualityThreshold = 0.7,
    this.maxHistorySize = 100,
  });
}

/// Represents the state of an exercise
enum ExerciseState { up, down, transitioning }

/// Represents the quality of a repetition
enum RepQuality {
  excellent,
  good,
  fair,
  poor;

  double get score => switch (this) {
    RepQuality.excellent => 4,
    RepQuality.good => 3,
    RepQuality.fair => 2,
    RepQuality.poor => 1,
  };
}

/// Data class for individual repetition information
class RepetitionData {
  final int repNumber;
  final DateTime timestamp;

  /// Duration of the rep in milliseconds
  final double duration;
  final RepQuality quality;
  final double confidence;
  final double formScore;
  final Map<String, dynamic> formMetrics;

  const RepetitionData({
    required this.repNumber,
    required this.timestamp,
    required this.duration,
    required this.quality,
    required this.confidence,
    required this.formScore,
    required this.formMetrics,
  });

  Map<String, dynamic> toMap() {
    return {
      'repNumber': repNumber,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'duration': '${duration / 1000} seconds',
      'quality': quality.toString(),
      'averageConfidence': confidence,
      'formScore': formScore,
      'formMetrics': formMetrics,
    };
  }
}

/// Represents the current state of rep counting
class RepCountingState {
  final int totalReps;
  final ExerciseState currentState;
  final RepetitionData? lastRep;
  final List<RepetitionData> allReps;

  const RepCountingState({required this.totalReps, required this.currentState, this.lastRep, required this.allReps});

  Map<String, dynamic> get statistics {
    return {
      'totalReps': totalReps,
      'averageFormScore': _getAverageFormScore(),
      'qualityDistribution': _getQualityDistribution(),
      'averageRepDuration': _getAverageRepDuration(),
      'bestRep': _getBestRep()?.toMap(),
      'worstRep': _getWorstRep()?.toMap(),
      'averageQuality': averageQuality.toString(),
    };
  }

  /// Get average quality from all completed repetitions
  RepQuality get averageQuality {
    if (allReps.isEmpty) return RepQuality.fair;

    final qualityScores = allReps.map((rep) => rep.quality.score).toList();

    final average = qualityScores.reduce((a, b) => a + b) / qualityScores.length;

    if (average >= 3.5) return RepQuality.excellent;
    if (average >= 2.5) return RepQuality.good;
    if (average >= 1.5) return RepQuality.fair;
    return RepQuality.poor;
  }

  /// Get average form score across all reps
  double _getAverageFormScore() {
    if (allReps.isEmpty) return 0.0;
    return allReps.map((r) => r.formScore).reduce((a, b) => a + b) / allReps.length;
  }

  /// Get distribution of rep qualities
  Map<String, int> _getQualityDistribution() {
    final distribution = <String, int>{'excellent': 0, 'good': 0, 'fair': 0, 'poor': 0};

    for (final rep in allReps) {
      distribution[rep.quality.toString().split('.').last] =
          (distribution[rep.quality.toString().split('.').last] ?? 0) + 1;
    }

    return distribution;
  }

  /// Get average rep duration
  double _getAverageRepDuration() {
    if (allReps.isEmpty) return 0.0;
    return allReps.map((r) => r.duration).reduce((a, b) => a + b) / allReps.length;
  }

  /// Get the best quality rep
  RepetitionData? _getBestRep() {
    if (allReps.isEmpty) return null;
    return allReps.reduce((a, b) => a.formScore > b.formScore ? a : b);
  }

  /// Get the worst quality rep
  RepetitionData? _getWorstRep() {
    if (allReps.isEmpty) return null;
    return allReps.reduce((a, b) => a.formScore < b.formScore ? a : b);
  }
}

/// Advanced repetition counter with form quality assessment
class RepsCounter {
  final PoseClassifier _classifier;
  final RepCountingConfig _config;

  // State tracking
  ExerciseState _currentState = ExerciseState.up;
  ExerciseState? _targetState; // Track what state we're trying to reach
  int _stableFrameCount = 0;
  int _totalReps = 0;
  DateTime? _lastRepTime;
  DateTime? _transitionStartTime;

  final List<RepetitionData> _repetitions = <RepetitionData>[];

  // Stream controllers for real-time updates
  final StreamController<RepCountingState> _stateController = StreamController<RepCountingState>.broadcast();
  final StreamController<RepetitionData> _repController = StreamController<RepetitionData>.broadcast();

  RepsCounter(this._classifier, {RepCountingConfig? config}) : _config = config ?? const RepCountingConfig();

  /// Stream of rep counting state updates
  Stream<RepCountingState> get stateStream => _stateController.stream;

  /// Stream of completed repetitions
  Stream<RepetitionData> get repStream => _repController.stream;

  /// Current rep counting state
  RepCountingState get currentState => RepCountingState(
    totalReps: _totalReps,
    currentState: _currentState,
    lastRep: _repetitions.isNotEmpty ? _repetitions.last : null,
    allReps: List.unmodifiable(_repetitions),
  );

  /// Process new pose detection results
  void processFrame(PoseDetectionResult poseResult) {
    if (!poseResult.hasPose || poseResult.visibleLandmarkCount < 10) {
      return; // Skip frames with poor pose detection
    }

    final probabilities = _classifier.classify(
      worldLandmarks: poseResult.worldLandmarks,
      imageLandmarks: poseResult.landmarks,
    );

    final upProbability = probabilities['up'] ?? 0.5;
    final downProbability = probabilities['down'] ?? 0.5;

    // Determine target state based on probabilities
    ExerciseState targetState;
    if (upProbability > _config.probabilityThreshold) {
      targetState = ExerciseState.up;
    } else if (downProbability > _config.probabilityThreshold) {
      targetState = ExerciseState.down;
    } else {
      targetState = ExerciseState.transitioning;
    }

    _updateState(targetState, poseResult, probabilities);

    // Emit current state
    _stateController.add(currentState);
  }

  /// Update exercise state and count repetitions
  void _updateState(ExerciseState targetState, PoseDetectionResult poseResult, Map<String, double> probabilities) {
    // Check if the target state has changed
    if (_targetState != targetState) {
      _targetState = targetState;
      _stableFrameCount = 1; // Start counting for the new target state
      return; // Exit early, need to accumulate frames for this new target
    }

    // Target state is the same as before, increment counter
    _stableFrameCount++;

    final timestamp = poseResult.timestamp;

    // Check if target state is different from current state and we have enough stable frames
    if (targetState != _currentState && _stableFrameCount >= _config.stateStabilityFrames) {
      // Prevent too frequent rep counting
      if (_lastRepTime != null && timestamp.difference(_lastRepTime!).inMilliseconds < _config.minRepInterval) {
        return;
      }

      final previousState = _currentState;
      _currentState = targetState;
      _stableFrameCount = 0;
      _targetState = null; // Reset target state tracking

      // Count rep when transitioning from down to up (completing a full cycle)
      if (previousState == ExerciseState.down && _currentState == ExerciseState.up) {
        _completeRepetition(timestamp, poseResult, probabilities);
      } else if (previousState == ExerciseState.up && _currentState == ExerciseState.down) {
        // Starting a new rep cycle
        _transitionStartTime = timestamp;
      }
    }
  }

  /// Complete a repetition and calculate quality metrics
  void _completeRepetition(DateTime timestamp, PoseDetectionResult poseResult, Map<String, double> probabilities) {
    _totalReps++;

    final duration = _transitionStartTime != null
        ? timestamp.difference(_transitionStartTime!).inMilliseconds.toDouble()
        : 0.0;

    final upProbability = probabilities['up'] ?? 0.5;
    final downProbability = probabilities['down'] ?? 0.5;

    // Confidence represents certainty: 0.0 (uncertain) to 1.0 (very certain)
    // Convert from probability space to confidence space
    final confidence = (max(upProbability, downProbability) - 0.5) * 2;

    // Calculate form metrics
    final formMetrics = _classifier.calculateFormMetrics(
      worldLandmarks: poseResult.worldLandmarks,
      imageLandmarks: poseResult.landmarks,
      position: _currentState == ExerciseState.up ? 'up' : 'down',
    );

    final formScore = _calculateFormScore(formMetrics); // Use current form score for this specific rep
    final quality = _determineRepQuality(formScore, confidence);

    final repData = RepetitionData(
      repNumber: _totalReps,
      timestamp: timestamp,
      duration: duration,
      quality: quality,
      confidence: confidence,
      formScore: formScore,
      formMetrics: Map.from(formMetrics), // Use the current form metrics
    );

    _repetitions.add(repData);
    _lastRepTime = timestamp;

    // Emit the new rep
    _repController.add(repData);
  }

  /// Calculate overall form score from individual metrics
  double _calculateFormScore(Map<String, dynamic> formMetrics) {
    if (formMetrics.isEmpty) return 0.5;

    final values = formMetrics.values.where((v) => !v['score'].isNaN).toList();
    if (values.isEmpty) return 0.5;

    return values.fold(0.0, (a, b) => a + b['score']) / values.length;
  }

  /// Determine rep quality based on form score and confidence
  RepQuality _determineRepQuality(double formScore, double confidence) {
    final combinedScore = formScore * 0.3 + confidence * 0.7;

    if (combinedScore >= 0.9) return RepQuality.excellent;
    if (combinedScore >= 0.75) return RepQuality.good;
    if (combinedScore >= 0.6) return RepQuality.fair;
    return RepQuality.poor;
  }

  /// Reset the rep counter
  void reset() {
    _currentState = ExerciseState.up;
    _targetState = null;
    _stableFrameCount = 0;
    _totalReps = 0;
    _lastRepTime = null;
    _transitionStartTime = null;
    _repetitions.clear();

    _stateController.add(currentState);
  }

  /// Dispose of resources
  void dispose() {
    _stateController.close();
    _repController.close();
  }
}
