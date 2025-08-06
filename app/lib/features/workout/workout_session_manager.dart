import 'dart:async';
import 'dart:developer' show log;

import 'package:easy_localization/easy_localization.dart';
import 'package:waico/core/repositories/user_repository.dart';
import 'package:waico/core/voice_chat_pipeline.dart';
import 'package:waico/features/workout/models/workout_plan.dart';
import 'package:waico/features/workout/pose_detection/exercise_classifiers/exercise_classifiers.dart';
import 'package:waico/features/workout/pose_detection/pose_detection_service.dart';
import 'package:waico/features/workout/pose_detection/pose_models.dart';
import 'package:waico/features/workout/pose_detection/reps_counter.dart';
import 'package:waico/features/workout/workout_feedback_manager.dart';
import 'package:waico/generated/locale_keys.g.dart';

/// Manages the state and flow of a workout session
class WorkoutSessionManager {
  final WorkoutSession session;
  final UserRepository userRepository;
  final VoiceChatPipeline voiceChatPipeline;
  final int workoutWeek;
  final int workoutSessionIndex;
  final bool enableVoiceChat;

  // Pose detection
  final PoseDetectionService poseDetectionService;
  StreamSubscription<PoseDetectionResult>? _poseDetectionSubscription;

  // Feedback management
  final WorkoutFeedbackManager? _feedbackManager;

  // Rep counting management
  StreamSubscription<RepetitionData>? _repStreamSubscription;
  final List<RepetitionData> _cachedReps = [];
  int? _lastExcellentRepSent;

  // Duration-based exercise feedback management
  DateTime? _lastExcellentFormFeedbackSent;

  // Timers
  Timer? _autoStartTimer;
  Timer? _exerciseDurationTimer;

  // Single State Management
  late WorkoutSessionState _state;
  final StreamController<WorkoutSessionState> _stateController = StreamController<WorkoutSessionState>.broadcast();

  // Duration-based exercise tracking
  _DurationBasedExerciseFormTracker? _durationFormTracker;
  StreamSubscription<_DurationBasedExerciseMetrics>? _durationMetricsSubscription;

  final String languageCode;

  WorkoutSessionManager({
    required this.session,
    UserRepository? userRepository,
    PoseDetectionService? poseDetectionService,
    required this.voiceChatPipeline,
    required this.workoutWeek,
    required this.workoutSessionIndex,
    required this.languageCode,
    this.enableVoiceChat = true,
  }) : userRepository = userRepository ?? UserRepository(),
       poseDetectionService = poseDetectionService ?? PoseDetectionService.instance,
       _feedbackManager = enableVoiceChat ? null : WorkoutFeedbackManager(languageCode: languageCode);

  /// Stream of workout session state changes.
  Stream<WorkoutSessionState> get stateStream => _stateController.stream;

  /// The most recent state object.
  WorkoutSessionState get currentState => _state;

  String get aiVoice => switch (languageCode) {
    'en' => 'am_fenrir',
    'fr' => 'ff_siwis',
    'es' => 'em_alex',
    _ => 'am_fenrir', // Default to English voice
  };

  /// Initialize the workout session manager
  Future<void> initialize() async {
    if (enableVoiceChat) {
      await voiceChatPipeline.startChat(voice: aiVoice);
      // We only start listening when the exercise starts
      await voiceChatPipeline.stopListeningToUser();
    }
    await _initializeCurrentExercise();
    _startPreExerciseOrRestTimer(duration: 20, isInitialStart: true);
  }

  /// Finds the first incomplete exercise and sets the initial state.
  Future<void> _initializeCurrentExercise() async {
    int initialIndex = 0;
    for (int i = 0; i < session.exercises.length; i++) {
      if (!await userRepository.isExerciseCompleted(workoutWeek, workoutSessionIndex, i)) {
        initialIndex = i;
        break;
      }
    }

    final exercise = session.exercises[initialIndex];
    final repsCounter = _createRepsCounter(exercise);

    _state = WorkoutSessionState(
      currentPhase: WorkoutPhaseType.preExercise,
      currentExerciseIndex: initialIndex,
      currentExercise: exercise,
      currentSet: 1,
      totalExercises: session.exercises.length,
      hasNextExercise: initialIndex < session.exercises.length - 1,
      hasPreviousExercise: initialIndex > 0,
      repsCounter: repsCounter,
    );
    _listenToRepStream(repsCounter);
    _emitState();
  }

  /// Central method to emit the current state to listeners.
  void _emitState() {
    if (!_stateController.isClosed) {
      _stateController.add(_state);
    }
  }

  /// Start the current exercise, cancelling any pending timers.
  Future<void> startCurrentExercise() async {
    _cancelTimers();

    _state = _state.copyWith(currentPhase: WorkoutPhaseType.exercising, restTimerValue: null);
    _emitState();

    if (enableVoiceChat) {
      await voiceChatPipeline.startListeningToUser();
    }

    if (_state.currentExercise.load.type == ExerciseLoadType.reps) {
      await _startPoseDetection();
    } else if (_state.currentExercise.load.type == ExerciseLoadType.duration) {
      await _startDurationExerciseTracking();
      _startExerciseDurationTimer();
    }
  }

  Future<void> _startDurationExerciseTracking() async {
    await _stopPoseDetection();
    _durationFormTracker?.metricsStream.drain();
    await _durationMetricsSubscription?.cancel();
    _durationFormTracker = null;

    final classifier = _createDurationBasedClassifier(_state.currentExercise);
    if (classifier == null) return;
    _durationFormTracker = _DurationBasedExerciseFormTracker(classifier);
    _durationMetricsSubscription = _durationFormTracker!.metricsStream.listen(_handleDurationMetrics);

    if (!poseDetectionService.isActive) {
      try {
        if (await poseDetectionService.start()) {
          _poseDetectionSubscription = poseDetectionService.landmarkStream.listen((result) {
            _durationFormTracker?.processFrame(result);
          });
        }
      } catch (e, s) {
        log('Error starting pose detection for duration-based', error: e, stackTrace: s);
      }
    } else {
      _poseDetectionSubscription = poseDetectionService.landmarkStream.listen((result) {
        _durationFormTracker?.processFrame(result);
      });
    }
  }

  ExerciseClassifier? _createDurationBasedClassifier(Exercise exercise) {
    final name = exercise.name.toLowerCase();
    if (name.contains('plank')) return PlankClassifier();
    // Add more duration-based classifiers as needed
    return null;
  }

  Future<void> _handleDurationMetrics(_DurationBasedExerciseMetrics metrics) async {
    log(
      'Handling duration metrics: ${metrics.formMetrics}, score: ${metrics.formScore}, correctness: ${metrics.correctness}',
    );
    // Provide feedback if form is poor or excellent
    final hasFeedback = metrics.formMetrics.values.any((v) => v is Map && v.containsKey('message'));
    if (hasFeedback) {
      if (enableVoiceChat) {
        await _sendDurationMetricsToAI(metrics, isFormFeedback: true);
      } else {
        log('Handling pre-recorded form feedback');
        await _handlePreRecordedFormFeedback(metrics.formMetrics);
      }
    } else if (metrics.formScore > 0.9) {
      // Check if we should send excellent form feedback (10 seconds gap for duration-based exercises) and
      // at least 3 seconds have passed since the exercise started. This is to prevent sending too many feedback in a short time.
      final now = DateTime.now();
      final shouldSend =
          (_exerciseDurationTimer?.tick ?? 0) > 3 &&
          (_lastExcellentFormFeedbackSent == null || now.difference(_lastExcellentFormFeedbackSent!).inSeconds >= 10);

      if (shouldSend) {
        if (enableVoiceChat) {
          if (await _sendDurationMetricsToAI(metrics, isFormFeedback: false)) {
            _lastExcellentFormFeedbackSent = now;
          }
        } else {
          await _feedbackManager?.playExcellentFormFeedback();
          _lastExcellentFormFeedbackSent = now;
        }
      }
    }
  }

  Future<bool> _sendDurationMetricsToAI(_DurationBasedExerciseMetrics metrics, {required bool isFormFeedback}) async {
    final exerciseName = _state.currentExercise.name;
    final feedbackType = isFormFeedback
        ? LocaleKeys.workout_exercise_ai_feedback_form_correction_needed.tr()
        : LocaleKeys.workout_exercise_ai_feedback_excellent_performance.tr();
    final message =
        '''<system>
${LocaleKeys.workout_exercise_ai_feedback_exercise_label.tr(namedArgs: {'exercise': exerciseName})}
${LocaleKeys.workout_exercise_ai_feedback_set_label.tr(namedArgs: {'current': _state.currentSet.toString(), 'total': _state.currentExercise.load.sets.toString()})}
${LocaleKeys.workout_exercise_ai_feedback_feedback_type_label.tr(namedArgs: {'type': feedbackType})}

${LocaleKeys.workout_exercise_ai_feedback_metrics_label.tr()}
${_state.exerciseTimerValue != null ? '- ${LocaleKeys.workout_exercise_ai_feedback_duration_label.tr(namedArgs: {'current': _state.exerciseTimerValue!.toString(), 'total': _state.currentExercise.load.duration.toString()})}\n' : ''}
- ${LocaleKeys.workout_exercise_ai_feedback_form_score_label.tr(namedArgs: {'score': metrics.formScore.toString()})}
- ${LocaleKeys.workout_exercise_ai_feedback_correctness_label.tr(namedArgs: {'score': metrics.correctness.toString()})}
${isFormFeedback ? '''
- ${LocaleKeys.workout_exercise_ai_feedback_form_feedback_label.tr()}
    ${metrics.formMetrics.entries.where((entry) => entry.value.containsKey('message')).map((entry) => '${entry.key}: score=${entry.value['score']}, feedback=${entry.value['message']}').join('\n    ')}
''' : ''}
</system>
''';
    log('\n\nSending duration metrics to AI: $message\n\n');
    return await voiceChatPipeline.addSystemMessage(message);
  }

  /// Go to the next exercise, triggering a rest period.
  Future<void> goToNextExercise() async {
    if (_state.hasNextExercise) {
      final restDuration = _state.currentExercise.restDuration;

      await _stopPoseDetection();
      if (enableVoiceChat) {
        await voiceChatPipeline.stopListeningToUser();
      }
      _cancelTimers();

      final newIndex = _state.currentExerciseIndex + 1;
      _updateExercise(newIndex);

      // Start rest timer for the duration specified by the PREVIOUS exercise
      _startPreExerciseOrRestTimer(duration: restDuration);
    }
  }

  /// Go to the previous exercise
  Future<void> goToPreviousExercise() async {
    if (_state.hasPreviousExercise) {
      await _stopPoseDetection();
      if (enableVoiceChat) {
        await voiceChatPipeline.stopListeningToUser();
      }
      _cancelTimers();

      final newIndex = _state.currentExerciseIndex - 1;
      _updateExercise(newIndex);
      _startPreExerciseOrRestTimer(duration: 20, isInitialStart: true);
    }
  }

  /// Mark the current exercise as complete and transition to the next state.
  Future<void> markCurrentExerciseAsComplete() async {
    await userRepository.setExerciseCompletion(workoutWeek, workoutSessionIndex, _state.currentExerciseIndex, true);

    if (_state.hasNextExercise) {
      await goToNextExercise();
    } else {
      await _stopPoseDetection();
      _cancelTimers();
      _state = _state.copyWith(currentPhase: WorkoutPhaseType.finished);
      _emitState();
    }
  }

  /// Go to a specific exercise by index
  Future<void> goToExercise(int index) async {
    if (index >= 0 && index < session.exercises.length) {
      await _stopPoseDetection();
      if (enableVoiceChat) {
        await voiceChatPipeline.stopListeningToUser();
      }
      _cancelTimers();
      _updateExercise(index);
      _startPreExerciseOrRestTimer(duration: 20, isInitialStart: true);
    }
  }

  /// Updates the state to a new exercise.
  void _updateExercise(int index) {
    final newExercise = session.exercises[index];
    final newRepsCounter = _createRepsCounter(newExercise);

    _repStreamSubscription?.cancel();
    _state.repsCounter?.dispose();

    _cachedReps.clear();
    _lastExcellentRepSent = null;
    _lastExcellentFormFeedbackSent = null;

    _state = _state.copyWith(
      currentExerciseIndex: index,
      currentExercise: newExercise,
      currentSet: 1,
      repsCounter: newRepsCounter,
      hasNextExercise: index < session.exercises.length - 1,
      hasPreviousExercise: index > 0,
    );
    _listenToRepStream(newRepsCounter);
    _emitState();
  }

  /// Listens to the rep stream from the provided counter.
  void _listenToRepStream(RepsCounter? repsCounter) {
    if (repsCounter != null) {
      _repStreamSubscription = repsCounter.repStream.listen(_handleRepetitionData);
    }
  }

  /// Create rep counter for the given exercise
  RepsCounter? _createRepsCounter(Exercise exercise) {
    if (exercise.load.type != ExerciseLoadType.reps) return null;
    final name = exercise.name.toLowerCase();
    if (name.contains('push') && name.contains('up')) return RepsCounter(_createPushUpClassifier(name));
    if (name.contains('squat')) return RepsCounter(_createSquatClassifier(name));
    if (name.contains('crunch')) return RepsCounter(_createCrunchClassifier(name));
    if (name.contains('superman')) return RepsCounter(SupermanClassifier());
    return null;
  }

  ExerciseClassifier _createPushUpClassifier(String exerciseName) {
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

  ExerciseClassifier _createSquatClassifier(String exerciseName) {
    if (exerciseName.contains('sumo')) {
      return SumoSquatClassifier();
    } else if (exerciseName.contains('split')) {
      return SplitSquatClassifier(frontLeg: SplitSquatSide.left);
    } else {
      return SquatClassifier();
    }
  }

  ExerciseClassifier _createCrunchClassifier(String exerciseName) {
    if (exerciseName.contains('reverse')) {
      return ReverseCrunchClassifier();
    } else if (exerciseName.contains('double')) {
      return DoubleCrunchClassifier();
    } else {
      return CrunchClassifier();
    }
  }

  Future<void> _startPoseDetection() async {
    if (poseDetectionService.isActive || _state.repsCounter == null) return;
    try {
      if (await poseDetectionService.start()) {
        _poseDetectionSubscription = poseDetectionService.landmarkStream.listen((result) {
          _state.repsCounter?.processFrame(result);
        });
      }
    } catch (e, s) {
      log('Error starting pose detection', error: e, stackTrace: s);
    }
  }

  Future<void> _stopPoseDetection() async {
    if (!poseDetectionService.isActive) return;
    try {
      await _poseDetectionSubscription?.cancel();
      _poseDetectionSubscription = null;
      await poseDetectionService.stop();

      await _durationMetricsSubscription?.cancel();
      _durationMetricsSubscription = null;
      _durationFormTracker = null;
    } catch (e, s) {
      log('Error stopping pose detection', error: e, stackTrace: s);
    }
  }

  Future<void> _handleRepetitionData(RepetitionData repData) async {
    final targetRepsPerSet = _state.currentExercise.load.reps;
    if (targetRepsPerSet != null && repData.repNumber >= _state.currentSet * targetRepsPerSet) {
      await Future.delayed(const Duration(milliseconds: 500));
      await _completeSet();
      return;
    }

    _cachedReps.add(repData);
    if (_cachedReps.length > 15) _cachedReps.removeAt(0);

    final hasFeedback = repData.formMetrics.values.any((v) => v is Map && v.containsKey('message'));
    if (hasFeedback) {
      if (enableVoiceChat) {
        await _sendRepDataToAI(repData, isFormFeedback: true);
      } else {
        await _handlePreRecordedFormFeedback(repData.formMetrics);
      }
    } else if (repData.quality == RepQuality.excellent) {
      // Check if we should send excellent form feedback (There needs to be at least 5 reps gap)
      // And at least 3 reps have been completed in the current set. This is to prevent sending
      // too many feedback in a short time.
      final shouldSend =
          repData.repNumber >= 3 &&
          (_lastExcellentRepSent == null || (repData.repNumber - _lastExcellentRepSent!) >= 5);
      if (shouldSend) {
        if (enableVoiceChat) {
          if (await _sendRepDataToAI(repData, isFormFeedback: false)) {
            _lastExcellentRepSent = repData.repNumber;
          }
        } else {
          await _feedbackManager?.playExcellentFormFeedback();
          _lastExcellentRepSent = repData.repNumber;
        }
      } else {
        if (enableVoiceChat) {
          await voiceChatPipeline.addSystemSpeech('${repData.repNumber}');
        } else {
          await _feedbackManager?.playRepCountingAudio(repData.repNumber);
        }
      }
    } else {
      if (enableVoiceChat) {
        await voiceChatPipeline.addSystemSpeech('${repData.repNumber}');
      } else {
        await _feedbackManager?.playRepCountingAudio(repData.repNumber);
      }
    }
  }

  Future<bool> _sendRepDataToAI(RepetitionData currentRep, {required bool isFormFeedback}) async {
    // Send the last 3 previous, unsent reps + the current rep to the AI
    final previousRepsToSend = _cachedReps.sublist(_cachedReps.length > 3 ? _cachedReps.length - 3 : 0)
      ..remove(currentRep); // Remove the current rep, as it will be included in the message separately
    final exerciseName = _state.currentExercise.name;
    final feedbackType = isFormFeedback
        ? LocaleKeys.workout_exercise_ai_feedback_form_correction_needed.tr()
        : LocaleKeys.workout_exercise_ai_feedback_excellent_performance.tr();
    final message =
        '''<system>
${LocaleKeys.workout_exercise_ai_feedback_exercise_label.tr(namedArgs: {'exercise': exerciseName})}
${LocaleKeys.workout_exercise_ai_feedback_set_label.tr(namedArgs: {'current': _state.currentSet.toString(), 'total': _state.currentExercise.load.sets.toString()})}
${LocaleKeys.workout_exercise_ai_feedback_feedback_type_label.tr(namedArgs: {'type': feedbackType})}

${LocaleKeys.workout_exercise_ai_feedback_recent_reps_label.tr()}
${previousRepsToSend.map((rep) => LocaleKeys.workout_exercise_ai_feedback_rep_summary.tr(namedArgs: {'number': rep.repNumber.toString(), 'score': rep.quality.score.toString(), 'quality': rep.quality.name, 'duration': (rep.duration / 1000).toString()})).join('\n')}

${LocaleKeys.workout_exercise_ai_feedback_current_rep_analysis.tr()}
- ${LocaleKeys.workout_exercise_ai_feedback_rep_label.tr(namedArgs: {'current': currentRep.repNumber.toString(), 'total': _state.currentExercise.load.reps.toString()})}
- ${LocaleKeys.workout_exercise_ai_feedback_score_label.tr(namedArgs: {'score': currentRep.quality.score.toString()})}
- ${LocaleKeys.workout_exercise_ai_feedback_quality_label.tr(namedArgs: {'quality': currentRep.quality.name})}
- ${LocaleKeys.workout_exercise_ai_feedback_rep_duration_label.tr(namedArgs: {'duration': (currentRep.duration / 1000).toString()})}
${isFormFeedback ? '''
- ${LocaleKeys.workout_exercise_ai_feedback_form_feedback_label.tr()}
    ${currentRep.formMetrics.entries.where((entry) => entry.value.containsKey('message')).map((entry) => '${entry.key}: score=${entry.value['score']}, feedback=${entry.value['message']}').join('\n    ')}
''' : ''}
</system>
''';

    log('\n\nSending reps metrics to AI: $message\n\n');

    final success = await voiceChatPipeline.addSystemMessage(message);

    if (success) {
      // Remove sent reps from cache
      _cachedReps.removeWhere((rep) => previousRepsToSend.any((sent) => sent.repNumber == rep.repNumber));
      _cachedReps.remove(currentRep); // Remove the current rep as well
    }
    return success;
  }

  /// Handle form feedback using pre-recorded audio when voice chat is disabled
  Future<void> _handlePreRecordedFormFeedback(Map<String, dynamic> formMetrics) async {
    if (_feedbackManager == null) return;

    final exerciseName = _state.currentExercise.name;

    // Find the first metric that has feedback to play
    for (final entry in formMetrics.entries) {
      if (entry.value is Map && entry.value.containsKey('message')) {
        final feedbackKey = entry.key;

        // Handle special cases
        if (feedbackKey == 'overall_visibility') {
          await _feedbackManager.playOverallVisibilityFeedback();
          return;
        } else {
          await _feedbackManager.playFormFeedbackAudio(exerciseName, feedbackKey);
          return;
        }
      }
    }
  }

  void _startPreExerciseOrRestTimer({required int duration, bool isInitialStart = false}) {
    _cancelTimers();
    if (duration <= 0) {
      startCurrentExercise();
      return;
    }
    _state = _state.copyWith(
      currentPhase: isInitialStart ? WorkoutPhaseType.preExercise : WorkoutPhaseType.resting,
      restTimerValue: duration,
    );
    _emitState();

    _autoStartTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final newTime = (_state.restTimerValue ?? 1) - 1;
      if (newTime > 0) {
        _state = _state.copyWith(restTimerValue: newTime);
        _emitState();
      } else {
        timer.cancel();
        _autoStartTimer = null;
        startCurrentExercise();
      }
    });
  }

  void _startExerciseDurationTimer() {
    _cancelTimers();
    final duration = _state.currentExercise.load.duration;
    if (duration == null || duration <= 0) {
      _completeSet();
      return;
    }
    _state = _state.copyWith(exerciseTimerValue: duration);
    _emitState();

    _exerciseDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final newTime = (_state.exerciseTimerValue ?? 1) - 1;
      if (newTime > 0) {
        _state = _state.copyWith(exerciseTimerValue: newTime);
        _emitState();
      } else {
        timer.cancel();
        _exerciseDurationTimer = null;
        _state = _state.copyWith(exerciseTimerValue: null);
        _emitState();
        _completeSet();
      }
    });
  }

  Future<void> _completeSet() async {
    await _stopPoseDetection();

    if (enableVoiceChat) {
      await voiceChatPipeline.stopListeningToUser();
    }

    if (_state.currentSet < _state.currentExercise.load.sets) {
      _state = _state.copyWith(currentSet: _state.currentSet + 1);
      _emitState();
      _startPreExerciseOrRestTimer(duration: _state.currentExercise.restDuration);
    } else {
      await markCurrentExerciseAsComplete();
    }
  }

  void _cancelTimers() {
    _autoStartTimer?.cancel();
    _autoStartTimer = null;
    _exerciseDurationTimer?.cancel();
    _exerciseDurationTimer = null;
  }

  Future<void> dispose() async {
    _cancelTimers();
    await _stopPoseDetection();
    await _repStreamSubscription?.cancel();
    _state.repsCounter?.dispose();
    await _durationMetricsSubscription?.cancel();
    _durationFormTracker = null;
    await _feedbackManager?.dispose();
    await _stateController.close();
  }
}

class _DurationBasedExerciseFormTracker {
  final ExerciseClassifier classifier;
  final StreamController<_DurationBasedExerciseMetrics> _metricsController =
      StreamController<_DurationBasedExerciseMetrics>.broadcast();
  _DurationBasedExerciseMetrics _pendingMetrics = _DurationBasedExerciseMetrics(
    formScore: 0.5,
    formMetrics: {},
    correctness: 0.5,
  );
  int _numAccumulatedMetrics = 0;
  var _lastEmittedTime = DateTime.now();

  _DurationBasedExerciseFormTracker(this.classifier) {
    if (!classifier.isDurationBased) {
      throw ArgumentError('Classifier must be a duration-based exercise classifier');
    }
  }

  void reset() {
    _pendingMetrics = _DurationBasedExerciseMetrics(formScore: 0.5, formMetrics: {}, correctness: 0.5);
    _numAccumulatedMetrics = 0;
    _lastEmittedTime = DateTime.now();
  }

  Stream<_DurationBasedExerciseMetrics> get metricsStream => _metricsController.stream;

  void processFrame(PoseDetectionResult poseResult) {
    if (!poseResult.hasPose || poseResult.visibleLandmarkCount < 10) {
      return; // Skip frames with poor pose detection
    }

    final formScore = classifier.classify(
      worldLandmarks: poseResult.worldLandmarks,
      imageLandmarks: poseResult.landmarks,
    );
    final formMetrics = classifier.calculateFormMetrics(
      worldLandmarks: poseResult.worldLandmarks,
      imageLandmarks: poseResult.landmarks,
    );
    _numAccumulatedMetrics++;
    _pendingMetrics = _DurationBasedExerciseMetrics(
      // For duration-based exercises, up is the probability of form correctness and down for incorrect
      correctness: _moveAverage(formScore['up'] ?? 0.5, _pendingMetrics.correctness, _numAccumulatedMetrics),
      formScore: _moveAverage(_calculateFormScore(formMetrics), _pendingMetrics.formScore, _numAccumulatedMetrics),
      formMetrics: formMetrics,
    );

    // Emit metrics every second
    if (_lastEmittedTime.difference(DateTime.now()).inSeconds.abs() >= 1) {
      log(
        'Emitting duration metrics: ${_pendingMetrics.formMetrics}, score: ${_pendingMetrics.formScore}, correctness: ${_pendingMetrics.correctness}',
      );
      _metricsController.add(_pendingMetrics);
      reset();
    }
  }

  /// Calculate a moving average prioritizing the most recent values
  double _moveAverage(double newValue, double currentAverage, int count) {
    if (count == 0) return newValue;
    return (currentAverage * count + newValue) / (count + 1);
  }

  /// Calculate overall form score from individual metrics
  double _calculateFormScore(Map<String, dynamic> formMetrics) {
    if (formMetrics.isEmpty) return 0.5;

    final values = formMetrics.values.where((v) => !v['score'].isNaN).toList();
    if (values.isEmpty) return 0.5;

    return values.fold(0.0, (a, b) => a + b['score']) / values.length;
  }
}

class _DurationBasedExerciseMetrics {
  /// The probability of the exercise being performed correctly (0.0 - 1.0).
  final double correctness;
  final double formScore;
  final Map<String, dynamic> formMetrics;

  _DurationBasedExerciseMetrics({required this.formScore, required this.formMetrics, required this.correctness});
}

/// The specific phase of the workout (e.g., exercising, resting).
enum WorkoutPhaseType {
  /// Waiting for the initial timer to complete before the first exercise.
  preExercise,

  /// Actively performing an exercise (rep counting or duration timer).
  exercising,

  /// Resting between sets or between exercises.
  resting,

  /// The entire workout session is complete.
  finished,
}

/// A single, immutable state object representing the entire workout session's current state for the UI.
class WorkoutSessionState {
  final WorkoutPhaseType currentPhase;
  final int currentExerciseIndex;
  final Exercise currentExercise;
  final int currentSet;
  final int totalExercises;
  final bool hasNextExercise;
  final bool hasPreviousExercise;
  final RepsCounter? repsCounter;
  final int? restTimerValue;
  final int? exerciseTimerValue;

  const WorkoutSessionState({
    required this.currentPhase,
    required this.currentExerciseIndex,
    required this.currentExercise,
    required this.currentSet,
    required this.totalExercises,
    required this.hasNextExercise,
    required this.hasPreviousExercise,
    this.repsCounter,
    this.restTimerValue,
    this.exerciseTimerValue,
  });

  WorkoutSessionState copyWith({
    WorkoutPhaseType? currentPhase,
    int? currentExerciseIndex,
    Exercise? currentExercise,
    int? currentSet,
    int? totalExercises,
    bool? hasNextExercise,
    bool? hasPreviousExercise,
    RepsCounter? repsCounter,
    int? restTimerValue,
    int? exerciseTimerValue,
  }) {
    return WorkoutSessionState(
      currentPhase: currentPhase ?? this.currentPhase,
      currentExerciseIndex: currentExerciseIndex ?? this.currentExerciseIndex,
      currentExercise: currentExercise ?? this.currentExercise,
      currentSet: currentSet ?? this.currentSet,
      totalExercises: totalExercises ?? this.totalExercises,
      hasNextExercise: hasNextExercise ?? this.hasNextExercise,
      hasPreviousExercise: hasPreviousExercise ?? this.hasPreviousExercise,
      repsCounter: repsCounter ?? this.repsCounter,
      restTimerValue: restTimerValue, // Nullable fields should be explicitly passed
      exerciseTimerValue: exerciseTimerValue, // Nullable fields should be explicitly passed
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is WorkoutSessionState &&
        other.currentPhase == currentPhase &&
        other.currentExerciseIndex == currentExerciseIndex &&
        other.currentExercise == currentExercise &&
        other.currentSet == currentSet &&
        other.totalExercises == totalExercises &&
        other.hasNextExercise == hasNextExercise &&
        other.hasPreviousExercise == hasPreviousExercise &&
        other.repsCounter == repsCounter &&
        other.restTimerValue == restTimerValue &&
        other.exerciseTimerValue == exerciseTimerValue;
  }

  @override
  int get hashCode {
    return currentPhase.hashCode ^
        currentExerciseIndex.hashCode ^
        currentExercise.hashCode ^
        currentSet.hashCode ^
        totalExercises.hashCode ^
        hasNextExercise.hashCode ^
        hasPreviousExercise.hashCode ^
        repsCounter.hashCode ^
        restTimerValue.hashCode ^
        exerciseTimerValue.hashCode;
  }
}
