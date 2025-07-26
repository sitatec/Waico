import 'dart:async';
import 'dart:developer' show log;

import 'package:waico/core/repositories/user_repository.dart';
import 'package:waico/core/voice_chat_pipeline.dart';
import 'package:waico/features/workout/models/workout_plan.dart';
import 'package:waico/features/workout/models/workout_progress.dart';
import 'package:waico/features/workout/pose_detection/exercise_classifiers/exercise_classifiers.dart';
import 'package:waico/features/workout/pose_detection/pose_detection_service.dart';
import 'package:waico/features/workout/pose_detection/pose_models.dart';
import 'package:waico/features/workout/pose_detection/reps_counter.dart';

/// Manages the state and flow of a workout session
class WorkoutSessionManager {
  final WorkoutSession session;
  final UserRepository userRepository;
  WorkoutProgress progress = WorkoutProgress.empty();
  final VoiceChatPipeline voiceChatPipeline; // Private state
  int _currentExerciseIndex = 0;
  RepsCounter? _repsCounter;
  final int workoutWeek;
  final int workoutSessionIndex;

  // Pose detection
  final PoseDetectionService _poseDetectionService = PoseDetectionService.instance;
  StreamSubscription<PoseDetectionResult>? _poseDetectionSubscription;
  bool _isPoseDetectionActive = false;

  // Stream controllers for state updates
  final StreamController<int> _exerciseIndexController = StreamController<int>.broadcast();
  final StreamController<Exercise> _currentExerciseController = StreamController<Exercise>.broadcast();

  WorkoutSessionManager({
    required this.session,
    UserRepository? userRepository,
    required this.voiceChatPipeline,
    required this.workoutWeek,
    required this.workoutSessionIndex,
  }) : userRepository = userRepository ?? UserRepository() {
    this.userRepository
        .getWorkoutProgress()
        .then((value) {
          progress = value;
          _initializeCurrentExercise();
        })
        .catchError((error, stackTrace) {
          log('Error loading workout progress', error: error, stackTrace: stackTrace);
          throw Exception('Failed to load workout progress During WorkoutSessionManager initialization');
        });
  }

  /// Stream of current exercise index changes
  Stream<int> get exerciseIndexStream => _exerciseIndexController.stream;

  /// Stream of current exercise changes
  Stream<Exercise> get currentExerciseStream => _currentExerciseController.stream;

  /// Current rep counter (null if current exercise doesn't support rep counting)
  RepsCounter? get repsCounter => _repsCounter;

  /// Whether pose detection is currently active
  bool get isPoseDetectionActive => _isPoseDetectionActive;

  /// Current exercise
  Exercise get currentExercise => session.exercises[_currentExerciseIndex];

  /// Current exercise index
  int get currentExerciseIndex => _currentExerciseIndex;

  /// Total number of exercises in the session
  int get totalExercises => session.exercises.length;

  /// Whether there is a next exercise
  bool get hasNextExercise => _currentExerciseIndex < session.exercises.length - 1;

  /// Whether there is a previous exercise
  bool get hasPreviousExercise => _currentExerciseIndex > 0;

  /// Initialize the current exercise (finds first incomplete exercise or defaults to first)
  void _initializeCurrentExercise() {
    // Find first incomplete exercise or default to first exercise
    _currentExerciseIndex = 0;
    for (int i = 0; i < session.exercises.length; i++) {
      final exerciseKey = WorkoutProgress.getExerciseKey(workoutWeek, workoutSessionIndex, i);
      if (!progress.isExerciseCompleted(exerciseKey)) {
        _currentExerciseIndex = i;
        break;
      }
    }
    _updateRepsCounter();
    _emitCurrentExercise();
  }

  /// Start the current exercise
  Future<void> startCurrentExercise() async {
    _updateRepsCounter();
    _emitCurrentExercise();
    await _startPoseDetection();
  }

  /// Go to the next exercise
  Future<void> goToNextExercise() async {
    if (hasNextExercise) {
      await _stopPoseDetection();
      _currentExerciseIndex++;
      _updateRepsCounter();
      _emitCurrentExercise();
      await _startPoseDetection();
    }
  }

  /// Go to the previous exercise
  Future<void> goToPreviousExercise() async {
    if (hasPreviousExercise) {
      await _stopPoseDetection();
      _currentExerciseIndex--;
      _updateRepsCounter();
      _emitCurrentExercise();
      await _startPoseDetection();
    }
  }

  /// Mark the current exercise as complete
  Future<void> markCurrentExerciseAsComplete() async {
    // Note: In a real implementation, this would update the workout progress
    // For now, we just move to the next exercise if available
    final exerciseKey = WorkoutProgress.getExerciseKey(workoutWeek, workoutSessionIndex, _currentExerciseIndex);
    progress = progress.withExerciseCompleted(exerciseKey, true);
    await userRepository.saveWorkoutProgress(progress);

    if (hasNextExercise) {
      await goToNextExercise();
    } else {
      // If this is the last exercise, stop pose detection
      await _stopPoseDetection();
    }
  }

  /// Go to a specific exercise by index
  Future<void> goToExercise(int index) async {
    if (index >= 0 && index < session.exercises.length) {
      await _stopPoseDetection();
      _currentExerciseIndex = index;
      _updateRepsCounter();
      _emitCurrentExercise();
      await _startPoseDetection();
    }
  }

  /// Create appropriate rep counter based on exercise name
  void _updateRepsCounter() {
    _repsCounter?.dispose();
    _repsCounter = _createRepsCounter(currentExercise);
  }

  /// Create rep counter for the given exercise
  RepsCounter? _createRepsCounter(Exercise exercise) {
    // Create appropriate rep counter based on exercise name. Since the workout plans are AI generated,
    // It's safer to use this parsing method than relying on exact values to determine exercise type.
    final exerciseName = exercise.name.toLowerCase();

    if (exerciseName.contains('push') && exerciseName.contains('up')) {
      return RepsCounter(_createPushUpClassifier(exerciseName));
    } else if (exerciseName.contains('squat')) {
      return RepsCounter(_createSquatClassifier(exerciseName));
    } else if (exerciseName.contains('crunch')) {
      return RepsCounter(_createCrunchClassifier(exerciseName));
    } else if (exerciseName.contains('superman')) {
      return RepsCounter(SupermanClassifier());
    }

    // If no specific classifier found, don't show rep counter
    return null;
  }

  /// Create push-up classifier based on exercise name
  PoseClassifier _createPushUpClassifier(String exerciseName) {
    if (exerciseName.contains('knee')) {
      return PushUpClassifier(type: PushUpType.knee);
    } else if (exerciseName.contains('wall')) {
      return PushUpClassifier(type: PushUpType.wall);
    } else if (exerciseName.contains('incline')) {
      return PushUpClassifier(type: PushUpType.incline);
    } else if (exerciseName.contains('decline')) {
      return PushUpClassifier(type: PushUpType.decline);
    } else if (exerciseName.contains('diamond') || exerciseName.contains('close')) {
      return PushUpClassifier(type: PushUpType.diamond);
    } else if (exerciseName.contains('wide')) {
      return PushUpClassifier(type: PushUpType.wide);
    } else {
      return PushUpClassifier(type: PushUpType.standard);
    }
  }

  /// Create squat classifier based on exercise name
  PoseClassifier _createSquatClassifier(String exerciseName) {
    if (exerciseName.contains('sumo')) {
      return SumoSquatClassifier();
    } else if (exerciseName.contains('split')) {
      // Default to left leg forward, could be made configurable
      return SplitSquatClassifier(frontLeg: SplitSquatSide.left);
    } else {
      return SquatClassifier();
    }
  }

  /// Create crunch classifier based on exercise name
  PoseClassifier _createCrunchClassifier(String exerciseName) {
    if (exerciseName.contains('reverse')) {
      return ReverseCrunchClassifier();
    } else if (exerciseName.contains('double')) {
      return DoubleCrunchClassifier();
    } else {
      return CrunchClassifier();
    }
  }

  /// Emit current exercise change
  void _emitCurrentExercise() {
    _exerciseIndexController.add(_currentExerciseIndex);
    _currentExerciseController.add(currentExercise);
  }

  /// Start pose detection and connect it to the reps counter
  Future<void> _startPoseDetection() async {
    if (_isPoseDetectionActive || _repsCounter == null) {
      return; // Already active or no rep counter to feed
    }

    try {
      final success = await _poseDetectionService.start();
      if (success) {
        _isPoseDetectionActive = true;

        // Subscribe to pose detection results and feed them to the reps counter
        _poseDetectionSubscription = _poseDetectionService.landmarkStream.listen(
          (PoseDetectionResult result) {
            _repsCounter?.processFrame(result);
          },
          onError: (error) {
            // Handle pose detection errors
            _isPoseDetectionActive = false;
          },
        );
      }
    } catch (e, s) {
      log('Error starting pose detection', error: e, stackTrace: s);
      _isPoseDetectionActive = false;
    }
  }

  /// Stop pose detection
  Future<void> _stopPoseDetection() async {
    if (!_isPoseDetectionActive) {
      return; // Already stopped
    }

    _isPoseDetectionActive = false;
    await _poseDetectionSubscription?.cancel();
    _poseDetectionSubscription = null;

    try {
      await _poseDetectionService.stop();
    } catch (e, s) {
      log('Error stopping pose detection', error: e, stackTrace: s);
      // Handle stop errors silently
    }
  }

  /// Dispose of resources
  Future<void> dispose() async {
    await _stopPoseDetection();
    _repsCounter?.dispose();
    await _exerciseIndexController.close();
    await _currentExerciseController.close();
  }
}
