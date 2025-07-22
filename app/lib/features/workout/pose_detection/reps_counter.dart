import 'dart:async';
import 'dart:collection';
import 'package:waico/features/workout/pose_detection/exercise_classifiers.dart';
import 'package:waico/features/workout/pose_detection/pose_models.dart';

/// Configuration for rep counting parameters
class RepCountingConfig {
  final double probabilityThreshold;
  final int stateStabilityFrames;
  final int minRepInterval;
  final double transitionSensitivity;

  const RepCountingConfig({
    this.probabilityThreshold = 0.65,
    this.stateStabilityFrames = 3,
    this.minRepInterval = 800,
    this.transitionSensitivity = 0.15,
  });
}

/// Represents a completed repetition
class RepetitionRecord {
  final int repNumber;
  final DateTime timestamp;
  final int duration;
  final double qualityScore;

  const RepetitionRecord({
    required this.repNumber,
    required this.timestamp,
    required this.duration,
    required this.qualityScore,
  });

  @override
  String toString() {
    return 'Rep $repNumber: ${duration}ms, quality: ${(qualityScore * 100).toStringAsFixed(1)}%';
  }
}

/// Simplified repetition counter that focuses on up/down transitions
class RepsCounter {
  final PoseClassifier _classifier;
  final RepCountingConfig _config;

  // Core state
  bool _isUp = false;
  int _stableFrameCount = 0;
  int _totalReps = 0;
  DateTime? _lastRepTime;
  DateTime? _repStartTime;
  bool _hasSeenDown = false; // Ensures we complete full cycles

  // Quality tracking
  final Queue<double> _probabilityHistory = Queue();
  final List<RepetitionRecord> _completedReps = [];

  // Events
  final StreamController<RepetitionRecord> _repController = StreamController<RepetitionRecord>.broadcast();

  Stream<RepetitionRecord> get repStream => _repController.stream;
  int get totalReps => _totalReps;
  List<RepetitionRecord> get completedReps => List.unmodifiable(_completedReps);

  double get averageQuality {
    if (_completedReps.isEmpty) return 0.0;
    return _completedReps.map((r) => r.qualityScore).reduce((a, b) => a + b) / _completedReps.length;
  }

  RepsCounter(this._classifier, {RepCountingConfig? config}) : _config = config ?? const RepCountingConfig();

  /// Process pose data and update rep count
  void processPoseData({required List<PoseLandmark> worldLandmarks, required List<PoseLandmark> imageLandmarks}) {
    try {
      final probabilities = _classifier.classify(worldLandmarks: worldLandmarks, imageLandmarks: imageLandmarks);

      final upProb = probabilities['up'] ?? 0.0;
      final downProb = probabilities['down'] ?? 0.0;

      // Track probability for quality assessment
      _probabilityHistory.add(upProb);
      if (_probabilityHistory.length > 10) {
        _probabilityHistory.removeFirst();
      }

      // Determine target state
      final shouldBeUp = _shouldBeUp(upProb, downProb);
      _updateState(shouldBeUp);
    } catch (e) {
      // Silent fail - pose detection can be noisy
    }
  }

  /// Determine if we should be in "up" state based on probabilities
  bool _shouldBeUp(double upProb, double downProb) {
    final threshold = _config.probabilityThreshold;
    final sensitivity = _config.transitionSensitivity;

    if (upProb > threshold && upProb > downProb + sensitivity) {
      return true;
    } else if (downProb > threshold && downProb > upProb + sensitivity) {
      return false;
    }
    // If unclear, maintain current state
    return _isUp;
  }

  /// Update state with stability checking
  void _updateState(bool shouldBeUp) {
    if (shouldBeUp == _isUp) {
      _stableFrameCount++;
      return;
    }

    _stableFrameCount = 1;

    // Require stability before changing state
    if (_stableFrameCount >= _config.stateStabilityFrames) {
      _changeState(shouldBeUp);
    }
  }

  /// Change state and handle rep counting
  void _changeState(bool newIsUp) {
    final oldIsUp = _isUp;
    _isUp = newIsUp;
    _stableFrameCount = 0;

    final now = DateTime.now();

    // Track when we see the down position
    if (!_isUp) {
      _hasSeenDown = true;
      if (_repStartTime == null) {
        _repStartTime = now;
      }
    }

    // Complete rep on up transition after seeing down
    if (!oldIsUp && _isUp && _hasSeenDown) {
      _completeRep(now);
    }
  }

  /// Complete a repetition
  void _completeRep(DateTime now) {
    // Check minimum interval
    if (_lastRepTime != null && now.difference(_lastRepTime!).inMilliseconds < _config.minRepInterval) {
      return;
    }

    _totalReps++;
    _lastRepTime = now;

    final duration = _repStartTime != null ? now.difference(_repStartTime!).inMilliseconds : 0;

    final rep = RepetitionRecord(
      repNumber: _totalReps,
      timestamp: now,
      duration: duration,
      qualityScore: _calculateQuality(),
    );

    _completedReps.add(rep);
    _repController.add(rep);

    // Reset for next rep
    _hasSeenDown = false;
    _repStartTime = now;
  }

  /// Calculate quality based on probability consistency
  double _calculateQuality() {
    if (_probabilityHistory.isEmpty) return 0.5;

    final avg = _probabilityHistory.reduce((a, b) => a + b) / _probabilityHistory.length;
    final variance =
        _probabilityHistory.map((p) => (p - avg) * (p - avg)).reduce((a, b) => a + b) / _probabilityHistory.length;

    // Lower variance = higher quality
    return (1.0 - (variance * 4.0)).clamp(0.0, 1.0);
  }

  /// Reset counter
  void reset() {
    _totalReps = 0;
    _isUp = false;
    _stableFrameCount = 0;
    _lastRepTime = null;
    _repStartTime = null;
    _hasSeenDown = false;
    _probabilityHistory.clear();
    _completedReps.clear();
  }

  /// Get session statistics
  Map<String, dynamic> getSessionStats() {
    return {
      'totalReps': _totalReps,
      'averageQuality': averageQuality,
      'isUp': _isUp,
      'lastRepQuality': _completedReps.isNotEmpty ? _completedReps.last.qualityScore : 0.0,
    };
  }

  void dispose() {
    _repController.close();
  }
}
