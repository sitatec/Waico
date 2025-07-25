import 'dart:async';
import 'dart:collection';
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
  final double duration; // Duration in milliseconds
  final RepQuality quality;
  final double confidence;
  final double formScore;
  final Map<String, double> formMetrics;

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
      'duration': duration,
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
  final double confidence;
  final RepetitionData? lastRep;
  final List<RepetitionData> allReps;
  final double averageFormScore;
  final RepQuality averageQuality;

  const RepCountingState({
    required this.totalReps,
    required this.currentState,
    required this.confidence,
    this.lastRep,
    required this.allReps,
    required this.averageFormScore,
    required this.averageQuality,
  });
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

  // Quality tracking - only for stable endpoint positions
  final Queue<double> _endpointConfidenceHistory = Queue();
  final Queue<Map<String, double>> _endpointFormMetricsHistory = Queue();
  final List<RepetitionData> _repetitions = <RepetitionData>[];

  // Current frame data (not stored in history until we reach an endpoint)
  double _currentConfidence = 0.0;
  Map<String, dynamic> _currentFormMetrics = {};

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
    confidence: _getAverageConfidence(),
    lastRep: _repetitions.isNotEmpty ? _repetitions.last : null,
    allReps: List.unmodifiable(_repetitions),
    averageFormScore: _getAverageFormScore(),
    averageQuality: _getAverageQuality(),
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
    // Confidence represents certainty: 0.0 (uncertain) to 1.0 (very certain)
    // Convert from probability space to confidence space
    final confidence = (max(upProbability, downProbability) - 0.5) * 2;

    // Calculate form metrics
    final formMetrics = _calculateFormMetrics(poseResult);

    // Store current frame data (will be saved to history only at stable endpoints)
    _currentConfidence = confidence;
    _currentFormMetrics = formMetrics;

    // Determine target state based on probabilities
    ExerciseState targetState;
    if (upProbability > _config.probabilityThreshold) {
      targetState = ExerciseState.up;
    } else if (downProbability > _config.probabilityThreshold) {
      targetState = ExerciseState.down;
    } else {
      targetState = ExerciseState.transitioning;
    }

    _updateState(targetState, poseResult.timestamp);

    // Emit current state
    _stateController.add(currentState);
  }

  /// Update exercise state and count repetitions
  void _updateState(ExerciseState targetState, DateTime timestamp) {
    // Check if the target state has changed
    if (_targetState != targetState) {
      _targetState = targetState;
      _stableFrameCount = 1; // Start counting for the new target state
      return; // Exit early, need to accumulate frames for this new target
    }

    // Target state is the same as before, increment counter
    _stableFrameCount++;

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

      // Record quality metrics only at stable endpoint positions
      _recordEndpointQuality();

      // Count rep when transitioning from down to up (completing a full cycle)
      if (previousState == ExerciseState.down && _currentState == ExerciseState.up) {
        _completeRepetition(timestamp);
      } else if (previousState == ExerciseState.up && _currentState == ExerciseState.down) {
        // Starting a new rep cycle
        _transitionStartTime = timestamp;
      }
    }
  }

  /// Record quality metrics when reaching a stable endpoint position
  void _recordEndpointQuality() {
    // Only record quality at stable positions (not during transitions)
    if (_currentState != ExerciseState.transitioning) {
      _endpointConfidenceHistory.add(_currentConfidence);
      if (_endpointConfidenceHistory.length > _config.maxHistorySize) {
        _endpointConfidenceHistory.removeFirst();
      }

      _endpointFormMetricsHistory.add(Map.from(_currentFormMetrics));
      if (_endpointFormMetricsHistory.length > _config.maxHistorySize) {
        _endpointFormMetricsHistory.removeFirst();
      }
    }
  }

  /// Complete a repetition and calculate quality metrics
  void _completeRepetition(DateTime timestamp) {
    _totalReps++;

    final duration = _transitionStartTime != null
        ? timestamp.difference(_transitionStartTime!).inMilliseconds.toDouble()
        : 0.0;

    final formScore = _calculateFormScore(_currentFormMetrics); // Use current form score for this specific rep
    final quality = _determineRepQuality(formScore, _currentConfidence);

    final repData = RepetitionData(
      repNumber: _totalReps,
      timestamp: timestamp,
      duration: duration,
      quality: quality,
      confidence: _currentConfidence,
      formScore: formScore,
      formMetrics: Map.from(_currentFormMetrics), // Use the current form metrics
    );

    _repetitions.add(repData);
    _lastRepTime = timestamp;

    // Emit the new rep
    _repController.add(repData);
  }

  /// Calculate form metrics based on pose landmarks
  Map<String, dynamic> _calculateFormMetrics(PoseDetectionResult poseResult) {
    return _classifier.calculateFormMetrics(
      worldLandmarks: poseResult.worldLandmarks,
      imageLandmarks: poseResult.landmarks,
    );
  }

  /// Calculate overall form score from individual metrics
  double _calculateFormScore(Map<String, dynamic> formMetrics) {
    if (formMetrics.isEmpty) return 0.5;

    final values = formMetrics.values.where((v) => !v['score'].isNaN).toList();
    if (values.isEmpty) return 0.5;

    return values.reduce((a, b) => a['score'] + b['score']) / values.length;
  }

  /// Determine rep quality based on form score and confidence
  RepQuality _determineRepQuality(double formScore, double confidence) {
    final combinedScore = (formScore * 0.4 + confidence * 0.7);

    if (combinedScore >= 0.9) return RepQuality.excellent;
    if (combinedScore >= 0.75) return RepQuality.good;
    if (combinedScore >= 0.6) return RepQuality.fair;
    return RepQuality.poor;
  }

  /// Get average confidence from recent endpoint history
  /// Confidence represents how certain the classifier is about pose states at stable positions
  /// 0.0 = completely uncertain (50/50), 1.0 = completely certain (90/10 or 10/90)
  double _getAverageConfidence() {
    if (_endpointConfidenceHistory.isEmpty) return 0.0;
    return _endpointConfidenceHistory.reduce((a, b) => a + b) / _endpointConfidenceHistory.length;
  }

  /// Get average form score from recent endpoint history
  double _getAverageFormScore() {
    if (_endpointFormMetricsHistory.isEmpty) return 0.0;

    double totalScore = 0.0;
    int count = 0;

    for (final metrics in _endpointFormMetricsHistory) {
      totalScore += _calculateFormScore(metrics);
      count++;
    }

    return count > 0 ? totalScore / count : 0.0;
  }

  /// Get average quality from all completed repetitions
  RepQuality _getAverageQuality() {
    if (_repetitions.isEmpty) return RepQuality.fair;

    final qualityScores = _repetitions.map((rep) => rep.quality.score).toList();

    final average = qualityScores.reduce((a, b) => a + b) / qualityScores.length;

    if (average >= 3.5) return RepQuality.excellent;
    if (average >= 2.5) return RepQuality.good;
    if (average >= 1.5) return RepQuality.fair;
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
    _endpointConfidenceHistory.clear();
    _endpointFormMetricsHistory.clear();
    _repetitions.clear();

    _stateController.add(currentState);
  }

  /// Get detailed statistics
  Map<String, dynamic> getStatistics() {
    return {
      'totalReps': _totalReps,
      'averageFormScore': _getAverageFormScore(),
      'averageQuality': _getAverageQuality().toString(),
      'averageConfidence': _getAverageConfidence(),
      'qualityDistribution': _getQualityDistribution(),
      'averageRepDuration': _getAverageRepDuration(),
      'bestRep': _getBestRep()?.toMap(),
      'worstRep': _getWorstRep()?.toMap(),
    };
  }

  /// Get distribution of rep qualities
  Map<String, int> _getQualityDistribution() {
    final distribution = <String, int>{'excellent': 0, 'good': 0, 'fair': 0, 'poor': 0};

    for (final rep in _repetitions) {
      distribution[rep.quality.toString().split('.').last] =
          (distribution[rep.quality.toString().split('.').last] ?? 0) + 1;
    }

    return distribution;
  }

  /// Get average rep duration
  double _getAverageRepDuration() {
    if (_repetitions.isEmpty) return 0.0;
    return _repetitions.map((r) => r.duration).reduce((a, b) => a + b) / _repetitions.length;
  }

  /// Get the best quality rep
  RepetitionData? _getBestRep() {
    if (_repetitions.isEmpty) return null;
    return _repetitions.reduce((a, b) => a.formScore > b.formScore ? a : b);
  }

  /// Get the worst quality rep
  RepetitionData? _getWorstRep() {
    if (_repetitions.isEmpty) return null;
    return _repetitions.reduce((a, b) => a.formScore < b.formScore ? a : b);
  }

  /// Dispose of resources
  void dispose() {
    _stateController.close();
    _repController.close();
  }
}
