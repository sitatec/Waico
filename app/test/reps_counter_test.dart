import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:waico/features/workout/pose_detection/exercise_classifiers/exercise_classifiers.dart';
import 'package:waico/features/workout/pose_detection/reps_counter.dart';
import 'package:waico/features/workout/pose_detection/pose_models.dart';

void main() {
  group('RepsCounter', () {
    late RepsCounter repsCounter;
    late MockPoseClassifier mockClassifier;

    setUp(() {
      mockClassifier = MockPoseClassifier();
      repsCounter = RepsCounter(mockClassifier);
    });

    tearDown(() {
      repsCounter.dispose();
    });

    test('should initialize with zero reps', () {
      final state = repsCounter.currentState;
      expect(state.totalReps, equals(0));
      expect(state.currentState, equals(ExerciseState.up));
      expect(state.allReps, isEmpty);
    });

    test('should count reps on down-up transitions', () async {
      final completer = Completer<RepetitionData>();
      repsCounter.repStream.listen((rep) => completer.complete(rep));

      // Simulate down-up transition
      mockClassifier.setResponse({'up': 0.2, 'down': 0.8});
      _simulateFrames(repsCounter, 5); // Go down

      mockClassifier.setResponse({'up': 0.8, 'down': 0.2});
      _simulateFrames(repsCounter, 5); // Go up

      await Future.delayed(Duration(milliseconds: 100));

      final state = repsCounter.currentState;
      expect(state.totalReps, equals(1));
    });

    test('should calculate form quality correctly', () async {
      final completer = Completer<RepetitionData>();
      repsCounter.repStream.listen((rep) => completer.complete(rep));

      // Simulate high-quality rep
      mockClassifier.setResponse({'up': 0.2, 'down': 0.9});
      _simulateHighQualityFrames(repsCounter, 5);

      mockClassifier.setResponse({'up': 0.9, 'down': 0.1});
      _simulateHighQualityFrames(repsCounter, 5);

      await Future.delayed(Duration(milliseconds: 100));

      final rep = await completer.future;
      expect(rep.quality, equals(RepQuality.excellent));
      expect(rep.formScore, greaterThan(0.8));
    });

    test('should respect minimum rep interval', () async {
      final config = RepCountingConfig(minRepInterval: 2000); // 2 seconds
      final counter = RepsCounter(mockClassifier, config: config);

      // First rep
      mockClassifier.setResponse({'up': 0.2, 'down': 0.8});
      _simulateFrames(counter, 5);
      mockClassifier.setResponse({'up': 0.8, 'down': 0.2});
      _simulateFrames(counter, 5);

      // Immediate second rep (should be ignored)
      mockClassifier.setResponse({'up': 0.2, 'down': 0.8});
      _simulateFrames(counter, 5);
      mockClassifier.setResponse({'up': 0.8, 'down': 0.2});
      _simulateFrames(counter, 5);

      await Future.delayed(Duration(milliseconds: 100));

      expect(counter.currentState.totalReps, equals(1));
      counter.dispose();
    });

    test('should provide accurate statistics', () async {
      // Use a shorter rep interval for testing
      final config = RepCountingConfig(minRepInterval: 50); // 50ms instead of 800ms
      final testCounter = RepsCounter(mockClassifier, config: config);

      // Simulate multiple reps with varying quality
      for (int i = 0; i < 5; i++) {
        mockClassifier.setResponse({'up': 0.2, 'down': 0.8});
        _simulateFrames(testCounter, 5);
        mockClassifier.setResponse({'up': 0.8, 'down': 0.2});
        _simulateFrames(testCounter, 5);
        await Future.delayed(Duration(milliseconds: 60)); // Slightly longer than minRepInterval
      }

      await Future.delayed(Duration(milliseconds: 100));

      final stats = testCounter.currentState.statistics;
      expect(stats['totalReps'], equals(5));
      expect(stats['averageFormScore'], isA<double>());
      expect(stats['qualityDistribution'], isA<Map<String, int>>());

      testCounter.dispose();
    });

    test('should reset correctly', () {
      // Add some reps first
      mockClassifier.setResponse({'up': 0.2, 'down': 0.8});
      _simulateFrames(repsCounter, 5);
      mockClassifier.setResponse({'up': 0.8, 'down': 0.2});
      _simulateFrames(repsCounter, 5);

      repsCounter.reset();

      final state = repsCounter.currentState;
      expect(state.totalReps, equals(0));
      expect(state.allReps, isEmpty);
      expect(state.currentState, equals(ExerciseState.up));
    });
  });

  group('RepCountingConfig', () {
    test('should use default values when not specified', () {
      const config = RepCountingConfig();
      expect(config.probabilityThreshold, equals(0.65)); // Back to 0.65 as per current implementation
      expect(config.stateStabilityFrames, equals(3));
      expect(config.minRepInterval, equals(800));
    });

    test('should use custom values when specified', () {
      const config = RepCountingConfig(probabilityThreshold: 0.8, stateStabilityFrames: 5, minRepInterval: 1500);
      expect(config.probabilityThreshold, equals(0.8));
      expect(config.stateStabilityFrames, equals(5));
      expect(config.minRepInterval, equals(1500));
    });
  });

  group('RepetitionData', () {
    test('should convert to map correctly', () {
      final rep = RepetitionData(
        repNumber: 1,
        timestamp: DateTime(2023, 1, 1),
        duration: 1500.0,
        quality: RepQuality.good,
        confidence: 0.85, // Keeping as 'confidence' as per current implementation
        formScore: 0.9,
        formMetrics: {'alignment': 0.95, 'speed': 0.85},
      );

      final map = rep.toMap();
      expect(map['repNumber'], equals(1));
      expect(map['quality'], equals('RepQuality.good'));
      expect(map['formScore'], equals(0.9));
      expect(map['formMetrics'], isA<Map<String, double>>());
    });
  });
}

/// Mock classifier for testing
class MockPoseClassifier extends PoseClassifier {
  Map<String, double> _response = {'up': 0.5, 'down': 0.5};

  MockPoseClassifier() : super(smoothingWindow: 1);

  void setResponse(Map<String, double> response) {
    _response = response;
  }

  @override
  Map<String, double> classify({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    return _response;
  }

  @override
  Map<String, double> calculateFormMetrics({
    required List<PoseLandmark> worldLandmarks,
    required List<PoseLandmark> imageLandmarks,
  }) {
    return {'overall_visibility': 0.9, 'test_metric': 0.8};
  }
}

/// Helper function to simulate multiple frames
void _simulateFrames(RepsCounter counter, int frameCount) {
  for (int i = 0; i < frameCount; i++) {
    counter.processFrame(_createMockPoseResult());
  }
}

/// Helper function to simulate high-quality frames
void _simulateHighQualityFrames(RepsCounter counter, int frameCount) {
  for (int i = 0; i < frameCount; i++) {
    counter.processFrame(_createHighQualityMockPoseResult());
  }
}

/// Create a mock pose detection result
PoseDetectionResult _createMockPoseResult() {
  final landmarks = List.generate(33, (index) => PoseLandmark(x: 0.5, y: 0.5, z: 0.0, visibility: 0.9));

  return PoseDetectionResult(
    landmarks: landmarks,
    worldLandmarks: landmarks,
    inferenceTime: 50,
    imageWidth: 640,
    imageHeight: 480,
    timestamp: DateTime.now(),
  );
}

/// Create a high-quality mock pose detection result
PoseDetectionResult _createHighQualityMockPoseResult() {
  final landmarks = List.generate(33, (index) => PoseLandmark(x: 0.5, y: 0.5, z: 0.0, visibility: 0.95));

  return PoseDetectionResult(
    landmarks: landmarks,
    worldLandmarks: landmarks,
    inferenceTime: 30,
    imageWidth: 640,
    imageHeight: 480,
    timestamp: DateTime.now(),
  );
}
