import 'dart:async';
import 'dart:developer' show log;

import 'package:waico/core/repositories/user_repository.dart';
import 'package:waico/core/voice_chat_pipeline.dart';
import 'package:waico/features/workout/models/workout_plan.dart';
import 'package:waico/features/workout/pose_detection/exercise_classifiers/exercise_classifiers.dart';
import 'package:waico/features/workout/pose_detection/pose_detection_service.dart';
import 'package:waico/features/workout/pose_detection/pose_models.dart';
import 'package:waico/features/workout/pose_detection/reps_counter.dart';

/// Manages the state and flow of a workout session
class WorkoutSessionManager {
  final WorkoutSession session;
  final UserRepository userRepository;
  final VoiceChatPipeline voiceChatPipeline;
  int _currentExerciseIndex = 0;
  RepsCounter? _repsCounter;
  final int workoutWeek;
  final int workoutSessionIndex;

  // Pose detection
  final PoseDetectionService poseDetectionService;
  StreamSubscription<PoseDetectionResult>? _poseDetectionSubscription;
  // Rep counting management
  StreamSubscription<RepetitionData>? _repStreamSubscription;
  final List<RepetitionData> _cachedReps = [];
  int? _lastExcellentRepSent;

  // Stream controllers for state updates
  final StreamController<int> _exerciseIndexController = StreamController<int>.broadcast();

  WorkoutSessionManager({
    required this.session,
    UserRepository? userRepository,
    PoseDetectionService? poseDetectionService,
    required this.voiceChatPipeline,
    required this.workoutWeek,
    required this.workoutSessionIndex,
  }) : userRepository = userRepository ?? UserRepository(),
       poseDetectionService = poseDetectionService ?? PoseDetectionService.instance;

  /// Stream of current exercise index changes
  Stream<int> get exerciseIndexStream => _exerciseIndexController.stream;

  /// Current rep counter (null if current exercise doesn't support rep counting)
  RepsCounter? get repsCounter => _repsCounter;

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

  /// Initialize the workout session manager
  Future<void> initialize() async {
    // Initialize the current exercise
    await voiceChatPipeline.startChat(voice: 'am_santa'); // TODO: get voice based on language
    // We start listening only when the exercise starts, to avoid peeking up user speech with others
    await voiceChatPipeline.stopListeningToUser();
    await _initializeCurrentExercise();
  }

  /// Initialize the current exercise (finds first incomplete exercise or defaults to first)
  Future<void> _initializeCurrentExercise() async {
    // Find first incomplete exercise or default to first exercise
    _currentExerciseIndex = 0;
    for (int i = 0; i < session.exercises.length; i++) {
      if (!await userRepository.isExerciseCompleted(workoutWeek, workoutSessionIndex, i)) {
        _currentExerciseIndex = i;
        break;
      }
    }
    _resetState();
    _emitCurrentExercise();
  }

  /// Start the current exercise
  Future<void> startCurrentExercise() async {
    await voiceChatPipeline.startListeningToUser();
    await _startPoseDetection();
  }

  /// Go to the next exercise
  Future<void> goToNextExercise() async {
    if (hasNextExercise) {
      await voiceChatPipeline.stopListeningToUser();
      await _stopPoseDetection();
      _currentExerciseIndex++;
      _resetState();
      _emitCurrentExercise();
      await _startPoseDetection();
    }
  }

  /// Go to the previous exercise
  Future<void> goToPreviousExercise() async {
    if (hasPreviousExercise) {
      await voiceChatPipeline.stopListeningToUser();
      await _stopPoseDetection();
      _currentExerciseIndex--;
      _resetState();
      _emitCurrentExercise();
    }
  }

  /// Mark the current exercise as complete
  Future<void> markCurrentExerciseAsComplete() async {
    // Note: In a real implementation, this would update the workout progress
    // For now, we just move to the next exercise if available
    await userRepository.setExerciseCompletion(workoutWeek, workoutSessionIndex, _currentExerciseIndex, true);

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
      _resetState();
      _emitCurrentExercise();
    }
  }

  void _resetState() {
    // Dispose previous rep counter and subscription
    _repStreamSubscription?.cancel();
    _repsCounter?.dispose();

    // Clear cached data for new exercise
    _cachedReps.clear();
    _lastExcellentRepSent = null;

    // Create new rep counter
    _repsCounter = _createRepsCounter(currentExercise);

    // Listen to rep stream if rep counter exists
    if (_repsCounter != null) {
      _repStreamSubscription = _repsCounter!.repStream.listen(_handleRepetitionData);
    }
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
  }

  /// Start pose detection and connect it to the reps counter
  Future<void> _startPoseDetection() async {
    if (poseDetectionService.isActive || _repsCounter == null) {
      return; // Already active or no rep counter to feed
    }

    try {
      final success = await poseDetectionService.start();
      if (success) {
        // Subscribe to pose detection results and feed them to the reps counter
        _poseDetectionSubscription = poseDetectionService.landmarkStream.listen((PoseDetectionResult result) {
          _repsCounter?.processFrame(result);
        });
      }
    } catch (e, s) {
      log('Error starting pose detection', error: e, stackTrace: s);
    }
  }

  /// Stop pose detection
  Future<void> _stopPoseDetection() async {
    try {
      if (!poseDetectionService.isActive) {
        return; // Already stopped
      }

      await _poseDetectionSubscription?.cancel();
      _poseDetectionSubscription = null;

      await poseDetectionService.stop();
    } catch (e, s) {
      log('Error stopping pose detection', error: e, stackTrace: s);
      // Handle stop errors silently
    }
  }

  /// Handle new repetition data from the rep counter
  Future<void> _handleRepetitionData(RepetitionData repData) async {
    // Add rep to cache and maintain max size of 15
    _cachedReps.add(repData);
    if (_cachedReps.length > 15) {
      _cachedReps.removeAt(0); // Remove oldest rep
    }

    final hasFeedbackMessage = repData.formMetrics.values.any((value) => value is Map && value.containsKey('message'));

    if (hasFeedbackMessage) {
      await _sendRepDataToAI(repData, isFormFeedback: true);
    } else if (repData.formScore > 9.0) {
      // Check if we should send excellent form feedback (at least 3 reps since last excellent feedback)
      final shouldSendExcellentFeedback =
          _lastExcellentRepSent == null || (repData.repNumber - _lastExcellentRepSent!) >= 3;

      if (shouldSendExcellentFeedback) {
        final success = await _sendRepDataToAI(repData, isFormFeedback: false);
        if (success) {
          _lastExcellentRepSent = repData.repNumber;
        }
      } else {
        // Just count out loud for excellent reps that don't need AI feedback
        await voiceChatPipeline.addSystemSpeech('${repData.repNumber}');
      }
    } else {
      // Regular rep - just count out loud
      await voiceChatPipeline.addSystemSpeech('${repData.repNumber}');
    }
  }

  /// Send repetition data along with cached reps to the AI Agent
  /// Returns true if successfully sent, false if pipeline was busy
  Future<bool> _sendRepDataToAI(RepetitionData currentRep, {required bool isFormFeedback}) async {
    final repsToSend = _cachedReps.sublist(
      // Send last 5 reps from cache
      _cachedReps.length > 5 ? _cachedReps.length - 5 : 0,
    );

    // Add current rep if not already in the list
    if (!repsToSend.any((rep) => rep.repNumber == currentRep.repNumber)) {
      repsToSend.add(currentRep);
    }

    // Prepare the message for AI Agent
    final exerciseName = currentExercise.name;
    final feedbackType = isFormFeedback ? "Form Correction Needed" : "Excellent Performance";

    final message =
        '''<system>
Exercise: $exerciseName
Feedback Type: $feedbackType

Recent Repetitions Data:
${repsToSend.map((rep) => 'Rep ${rep.repNumber}: Score ${rep.formScore}, Quality: ${rep.quality.name}, Duration: ${rep.duration / 1000} seconds').join('\n')}

Current Rep Analysis:
- Rep Number: ${currentRep.repNumber}
- Form Score: ${currentRep.formScore}
- Quality: ${currentRep.quality}${isFormFeedback ? '''
- Duration: ${currentRep.duration / 1000} seconds
- Form Feedback: 
    ${currentRep.formMetrics.entries.where((entry) => entry.value is Map && entry.value.containsKey('message')).map((entry) => '${entry.key}: score=${entry.value['score']}, feedback=${entry.value['message']}').join('\n    ')}
''' : ''}
</system>
''';

    // Send to AI Agent
    final success = await voiceChatPipeline.addSystemMessage(message);

    if (success) {
      // Remove sent reps from cache
      _cachedReps.removeWhere((rep) => repsToSend.any((sent) => sent.repNumber == rep.repNumber));
    }

    return success;
  }

  /// Dispose of resources
  Future<void> dispose() async {
    await _stopPoseDetection();
    await _repStreamSubscription?.cancel();
    _repsCounter?.dispose();
    await _exerciseIndexController.close();
  }
}
