import 'dart:developer' show log;

import 'package:meta/meta.dart';
import 'package:waico/core/ai_models/chat_model.dart';
import 'package:waico/features/workout/models/workout_setup_data.dart';
import 'package:waico/features/workout/models/workout_plan.dart';

/// Progress data containing both parsed structure and raw text
class WorkoutGenerationProgress {
  /// Parsed progress structure: {"Week 1": [WorkoutSession], "Week 2": []}
  final Map<String, List<WorkoutSession>> parsedProgress;

  /// Raw text being generated
  final String rawText;

  const WorkoutGenerationProgress({required this.parsedProgress, required this.rawText});
}

/// Generates personalized workout plans using AI based on user setup data
class WorkoutPlanGenerator {
  late final ChatModel _chatModel;

  static const String _systemPrompt = r'''
You are an expert personal trainer and exercise physiologist with over 15 years of experience designing customized workout programs. You specialize in creating safe, effective, and sustainable bodyweight workout plans tailored to individual goals, and workout experience levels.

Your expertise includes:
- Exercise physiology and biomechanics
- Adaptation strategies for different fitness levels (beginner, intermediate, advanced)
- Providing rest periods appropriate for exercise intensity


**STRUCTURED TEXT FORMAT (use EXACTLY this format):**

PLAN_NAME: [Short, motivating name for the workout plan]
DESCRIPTION: [Brief overview of the plan's approach and benefits (1-3 sentences)]
DIFFICULTY: [Beginner/Intermediate/Advanced]
FOCUS: [Main focus for this week]

SESSION_NAME: [Day - Body part, e.g: Monday - Full Body]
SESSION_TYPE: [cardio/strength/endurance/flexibility]
DURATION: [Duration in minutes]

EXERCISE: [Exercise name from allowed list]
TARGET_MUSCLES: [muscle1, muscle2, muscle3]
LOAD_TYPE: [reps/duration]
SETS: [number]
REPS: [number, only for reps-based exercises]
DURATION: [seconds, only for duration-based exercises]
REST: [rest duration in seconds]

[Repeat EXERCISE block for each exercise in the session]
[Repeat SESSION_NAME block for each session in the week]

IMPORTANT RULES:
- **ALLOWED EXERCISES (use EXACTLY these names):** Push-Up, Knee Push-Up, Wall Push-Up, Incline Push-Up, Decline Push-Up, Diamond Push-Up, Wide Push-Up, Squat, Sumo Squat, Split Squat (Right), Split Squat (Left), Crunch, Reverse Crunch, Double Crunch, Superman, Superman Pulse, Y Superman, Wall Sit, Plank, Side Plank, Jumping Jacks, High Knees, Burpees, Mountain Climbers
- "Split Squat (Right)" and "Split Squat (Left)" must always follow each other - they should not be used separately or have another exercise in between them.
- No equipment available, choose only bodyweight exercises from the allowed exercises list
- Use ONLY the specified structured text format above - NO JSON, NO other formats

**EXAMPLE:**
PLAN_NAME: Full Body Strength Builder
DESCRIPTION: A comprehensive bodyweight program focusing on building strength across all major muscle groups. Perfect for developing functional fitness and muscle endurance.
DIFFICULTY: Intermediate
FOCUS: Foundation building and strength development

SESSION_NAME: Monday - Upper Body
SESSION_TYPE: strength
DURATION: 30

EXERCISE: Push-Up
TARGET_MUSCLES: chest, shoulders, triceps
LOAD_TYPE: reps
REPS: 12
SETS: 3
REST: 60

EXERCISE: Plank
TARGET_MUSCLES: core, shoulders
LOAD_TYPE: duration
DURATION: 30
SETS: 3
REST: 45

SESSION_NAME: Wednesday - Lower Body
SESSION_TYPE: strength
DURATION: 25

EXERCISE: Squat
TARGET_MUSCLES: quadriceps, glutes
LOAD_TYPE: reps
REPS: 15
SETS: 3
REST: 60
''';

  WorkoutPlanGenerator() {
    _chatModel = ChatModel(systemPrompt: _systemPrompt);
  }

  /// Generates a personalized workout plan based on the provided setup data
  ///
  /// Takes [WorkoutSetupData] containing user preferences, goals, and constraints
  /// Returns a [WorkoutPlan] with a structured, progressive workout program
  ///
  /// [progressCallback] is called during generation with WorkoutGenerationProgress containing:
  /// - parsedProgress: {"Week 1": [SessionProgress], "Week 2": []}
  /// - rawText: The current raw structured text being generated
  /// When a week is being generated but no sessions are ready, an empty array is provided.
  ///
  /// Throws [WorkoutPlanGenerationException] if plan generation fails
  Future<WorkoutPlan> generate(
    WorkoutSetupData setupData, {
    void Function(WorkoutGenerationProgress)? progressCallback,
  }) async {
    try {
      await _chatModel.initialize();

      final prompt = _buildPrompt(setupData);
      log('WorkoutPlanGenerator: Generating workout plan for user with goals: ${setupData.primaryGoal}');

      final response = StringBuffer();
      final progressTracker = _WorkoutProgressTracker(progressCallback);

      await for (final chunk in _chatModel.sendMessageStream(prompt)) {
        response.write(chunk);
        // Try to parse progress incrementally
        progressTracker.updateProgress(response.toString());
      }

      final responseText = response.toString().trim();
      // TODO: remove this log in production
      log(
        'WorkoutPlanGenerator: Received response: \n#------------------------#\n\n$responseText\n\n#------------------------#',
      );

      try {
        // Currently mediapipe's Gemma3n is in preview and only support 4096 tokens
        // I also noticed that it often generate malformed JSON when the schema is complex.
        // To simplify the schema, we ask Gemma to generate in Structured text and for one week only with only a few informations
        // And we fill the rest of the data and weeks programmatically.

        final parsedPlan = _parseStructuredText(responseText);

        // Add the programmatic data (weeks, sessions per week, etc.)
        parsedPlan["totalWeeks"] = 4;
        parsedPlan["workoutsPerWeek"] = setupData.selectedWeekDays.length;
        parsedPlan["weeklyPlans"] = [];

        final referencePlan = parsedPlan["plan"] as Map<String, dynamic>;

        // Create 4 weeks with progressive intensity
        for (int i = 1; i <= 4; i++) {
          final plan = Map.of(referencePlan);
          plan["week"] = i;
          if (i > 2) {
            plan["focus"] = "Increase intensity/volume";

            // Progressively increase exercise difficulty
            for (final session in plan["workoutSessions"] as List<dynamic>) {
              if (session is Map<String, dynamic>) {
                // Increase estimated duration by 5-10% for each week
                final estimatedDuration = session["estimatedDuration"] as int? ?? 0;
                session["estimatedDuration"] = (estimatedDuration + (estimatedDuration * 0.05 * i)).round();

                // Adjust exercises based on week
                final exercises = session["exercises"] as List<dynamic>?;
                if (exercises != null) {
                  for (final exercise in exercises) {
                    if (exercise is Map<String, dynamic>) {
                      // Increase reps or duration based on week
                      final load = exercise["load"] as Map<String, dynamic>?;
                      if (load != null) {
                        if (load["type"] == "reps") {
                          final reps = load["reps"] as int? ?? 0;
                          load["reps"] = (reps + (reps * 0.05 * i)).round();
                        } else if (load["type"] == "duration") {
                          final duration = load["duration"] as int? ?? 0;
                          load["duration"] = (duration + (duration * 0.05 * i)).round();
                        }
                      }
                    }
                  }
                }
              }
            }
          }
          parsedPlan["weeklyPlans"].add(plan);
        }

        return WorkoutPlan.fromJson(parsedPlan);
      } catch (parseError) {
        log('WorkoutPlanGenerator: Text parsing failed', error: parseError);
        throw WorkoutPlanGenerationException(
          'Failed to parse workout plan structured text response',
          parseError is Exception ? parseError : Exception(parseError.toString()),
        );
      }
    } catch (e, stackTrace) {
      log('WorkoutPlanGenerator: Failed to generate workout plan', error: e, stackTrace: stackTrace);
      if (e is WorkoutPlanGenerationException) rethrow;

      throw WorkoutPlanGenerationException(
        'Failed to generate workout plan: ${e.toString()}',
        e is Exception ? e : Exception(e.toString()),
      );
    } finally {
      await _chatModel.dispose();
    }
  }

  /// Builds a comprehensive prompt from user setup data
  String _buildPrompt(WorkoutSetupData setupData) {
    final buffer = StringBuffer();

    buffer.writeln('Create a personalized workout plan based on the following user data:');
    buffer.writeln();

    // Physical stats
    buffer.writeln('Physical Profile:');
    if (setupData.age != null) buffer.writeln('- Age: ${setupData.age} years');
    if (setupData.gender != null) buffer.writeln('- Gender: ${setupData.gender}');
    if (setupData.weight != null) buffer.writeln('- Weight: ${setupData.weight} kg');
    if (setupData.height != null) buffer.writeln('- Height: ${setupData.height} cm');
    if (setupData.bmi != null) buffer.writeln('- BMI: ${setupData.bmi?.toStringAsFixed(1)}');
    buffer.writeln();

    // Fitness level and experience
    buffer.writeln('Fitness Background:');
    if (setupData.currentFitnessLevel != null) {
      buffer.writeln('- Current fitness level: ${setupData.currentFitnessLevel}');
    }
    if (setupData.experienceLevel != null) {
      buffer.writeln('- Exercise experience: ${setupData.experienceLevel}');
    }
    buffer.writeln(
      '- Weekly workout frequency: ${setupData.selectedWeekDays.join(', ')} (${setupData.selectedWeekDays.length} sessions per week)',
    );
    buffer.writeln('- Preferred workout duration: ${setupData.workoutDurationPreference} minutes');
    buffer.writeln();

    // Goals and preferences
    buffer.writeln('Goals and Preferences:');
    if (setupData.primaryGoal != null) {
      buffer.writeln('- Primary goal: ${setupData.primaryGoal}');
    }
    if (setupData.targetWeight != null) {
      buffer.writeln('- Target weight: ${setupData.targetWeight}');
    }
    // if (setupData.timeframe != null) {
    // buffer.writeln('- Timeframe: ${setupData.timeframe}');
    // TODO: Uncomment above when the full context of gemma3n is available in mediapipe
    // }
    buffer.writeln('- Timeframe: 2 Weeks'); // Fixed to 2 weeks for now

    if (setupData.specificGoals.isNotEmpty) {
      buffer.writeln('- Specific goals: ${setupData.specificGoals.join(", ")}');
    }

    buffer.writeln();

    buffer.writeln('Please generate a comprehensive workout plan that:');
    buffer.writeln('1. Matches the user\'s fitness level and experience');
    buffer.writeln('2. Aligns with their specific goals and preferences');
    buffer.writeln('3. Fits within their time constraints');
    buffer.writeln('4. Uses ONLY the structured text format specified above');

    return buffer.toString();
  }

  /// Parses the structured text format from the AI response
  /// Made public for testing purposes
  @visibleForTesting
  Map<String, dynamic> parseStructuredText(String responseText) {
    return _parseStructuredText(responseText);
  }

  /// Parses the structured text format from the AI response
  Map<String, dynamic> _parseStructuredText(String responseText) {
    final lines = responseText.split('\n').map((line) => line.trim()).toList();
    final result = <String, dynamic>{};
    final sessions = <Map<String, dynamic>>[];

    String? planFocus;
    Map<String, dynamic>? currentSession;
    final currentExercises = <Map<String, dynamic>>[];
    Map<String, dynamic>? currentExercise;

    for (final line in lines) {
      if (line.isEmpty) continue;

      if (line.startsWith('PLAN_NAME:')) {
        result['planName'] = line.substring(10).trim();
      } else if (line.startsWith('DESCRIPTION:')) {
        result['description'] = line.substring(12).trim();
      } else if (line.startsWith('DIFFICULTY:')) {
        result['difficulty'] = line.substring(11).trim();
      } else if (line.startsWith('FOCUS:')) {
        planFocus = line.substring(6).trim();
      } else if (line.startsWith('SESSION_NAME:')) {
        // Save previous session if it exists
        if (currentSession != null) {
          // Add the current exercise if it exists
          if (currentExercise != null) {
            currentExercises.add(Map<String, dynamic>.from(currentExercise));
            currentExercise = null;
          }

          currentSession['exercises'] = List<Map<String, dynamic>>.from(currentExercises);
          sessions.add(currentSession);
          currentExercises.clear();
        }

        // Start a new session
        currentSession = <String, dynamic>{};
        currentSession['sessionName'] = line.substring(13).trim();
      } else if (currentSession != null) {
        // Inside a session
        if (line.startsWith('SESSION_TYPE:')) {
          currentSession['type'] = line.substring(13).trim();
        } else if (line.startsWith('DURATION:')) {
          currentSession['estimatedDuration'] = int.tryParse(line.substring(9).trim()) ?? 30;
        } else if (line.startsWith('EXERCISE:')) {
          // Save previous exercise if exists
          if (currentExercise != null) {
            currentExercises.add(Map<String, dynamic>.from(currentExercise));
          }
          // Start new exercise
          currentExercise = <String, dynamic>{};
          currentExercise['name'] = line.substring(9).trim();
        } else if (currentExercise != null) {
          // Inside an exercise
          if (line.startsWith('TARGET_MUSCLES:')) {
            final musclesText = line.substring(15).trim();
            currentExercise['targetMuscles'] = musclesText
                .split(',')
                .map((m) => m.trim())
                .where((m) => m.isNotEmpty)
                .toList();
          } else if (line.startsWith('LOAD_TYPE:')) {
            final loadType = line.substring(10).trim();
            currentExercise['load'] = <String, dynamic>{'type': loadType};
          } else if (line.startsWith('SETS:')) {
            final sets = int.tryParse(line.substring(5).trim()) ?? 1;
            final load = currentExercise['load'] as Map<String, dynamic>? ?? <String, dynamic>{};
            load['sets'] = sets;
            currentExercise['load'] = load;
          } else if (line.startsWith('REPS:')) {
            final repsText = line.substring(5).trim();
            if (repsText.isNotEmpty) {
              final reps = int.tryParse(repsText) ?? 1;
              final load = currentExercise['load'] as Map<String, dynamic>? ?? <String, dynamic>{};
              load['reps'] = reps;
              currentExercise['load'] = load;
            }
          } else if (line.startsWith('DURATION:')) {
            final durationText = line.substring(9).trim();
            if (durationText.isNotEmpty) {
              final duration = int.tryParse(durationText) ?? 30;
              final load = currentExercise['load'] as Map<String, dynamic>? ?? <String, dynamic>{};
              load['duration'] = duration;
              currentExercise['load'] = load;
            }
          } else if (line.startsWith('REST:')) {
            final rest = int.tryParse(line.substring(5).trim()) ?? 60;
            currentExercise['restDuration'] = rest;
          }
        }
      }
    }

    // Don't forget the last session and exercise
    if (currentExercise != null) {
      currentExercises.add(Map<String, dynamic>.from(currentExercise));
    }
    if (currentSession != null) {
      currentSession['exercises'] = List<Map<String, dynamic>>.from(currentExercises);
      sessions.add(currentSession);
    }

    // Build the plan structure
    result['plan'] = {'focus': planFocus ?? 'General fitness', 'workoutSessions': sessions};

    return result;
  }

  /// Disposes of the chat model resources
  Future<void> dispose() async {
    try {
      await _chatModel.dispose();
    } catch (e) {
      // Ignore disposal errors if chat model was never initialized
      log('WorkoutPlanGenerator: Error during disposal (safe to ignore): $e');
    }
  }
}

/// Tracks workout plan generation progress and parses weeks/sessions incrementally
///
/// This class provides performance-optimized progress tracking by:
/// 1. Incrementally parsing structured text as it streams in (supports partial/incomplete text)
/// 2. Using efficient line-by-line parsing for structured text boundary detection
/// 3. Caching processed content to avoid redundant work
/// 4. Smart text completion for parsing incomplete structures
/// 5. Using pattern matching for partial text structures
/// 6. Only triggering callbacks when progress actually changes
class _WorkoutProgressTracker {
  final void Function(WorkoutGenerationProgress)? _progressCallback;
  Map<String, List<WorkoutSession>> _currentProgress = {};
  String _lastProcessedContent = '';

  _WorkoutProgressTracker(this._progressCallback);

  /// Resets the progress tracker for reuse
  void reset() {
    _currentProgress.clear();
    _lastProcessedContent = '';
  }

  void updateProgress(String textContent) {
    if (_progressCallback == null || textContent.length <= _lastProcessedContent.length) {
      return;
    }

    try {
      // Parse sessions incrementally from the streaming text content
      final newProgress = _parseSessionsIncrementally(textContent);

      // Only call callback if progress has changed
      if (_hasProgressChanged(newProgress)) {
        _currentProgress = Map<String, List<WorkoutSession>>.from(newProgress);
      }

      final progressData = WorkoutGenerationProgress(
        parsedProgress: Map<String, List<WorkoutSession>>.from(_currentProgress),
        rawText: textContent,
      );
      _progressCallback(progressData);

      _lastProcessedContent = textContent;
    } catch (e) {
      log('WorkoutProgressTracker: Failed to update progress', error: e);
    }
  }

  /// Parses sessions incrementally from streaming structured text content
  /// Uses pattern matching to find sessions as they appear in the stream
  Map<String, List<WorkoutSession>> _parseSessionsIncrementally(String textContent) {
    final progress = <String, List<WorkoutSession>>{'Sessions': <WorkoutSession>[]};
    final sessions = <WorkoutSession>[];

    // Split into lines and find complete sessions
    final lines = textContent.split('\n').map((line) => line.trim()).toList();

    Map<String, dynamic>? currentSession;
    final currentExercises = <Map<String, dynamic>>[];
    Map<String, dynamic>? currentExercise;

    for (final line in lines) {
      if (line.isEmpty) continue;

      if (line.startsWith('SESSION_NAME:')) {
        // Save previous session if it exists
        if (currentSession != null && currentSession.containsKey('sessionName')) {
          // Add the current exercise if it exists
          if (currentExercise != null) {
            currentExercises.add(Map<String, dynamic>.from(currentExercise));
            currentExercise = null;
          }

          currentSession['exercises'] = List<Map<String, dynamic>>.from(currentExercises);

          try {
            final session = WorkoutSession(
              sessionName: currentSession['sessionName'] as String? ?? 'Workout Session',
              type: currentSession['type'] as String? ?? 'strength',
              estimatedDuration: currentSession['estimatedDuration'] as int? ?? 30,
              exercises: currentExercises.map((exerciseMap) {
                try {
                  return Exercise(
                    name: exerciseMap['name'] as String? ?? 'Unknown Exercise',
                    targetMuscles: List<String>.from(exerciseMap['targetMuscles'] as List? ?? []),
                    load: ExerciseLoad(
                      type: ExerciseLoadType.fromString(exerciseMap['load']?['type'] as String? ?? 'reps'),
                      sets: exerciseMap['load']?['sets'] as int? ?? 1,
                      reps: exerciseMap['load']?['reps'] as int?,
                      duration: exerciseMap['load']?['duration'] as int?,
                    ),
                    restDuration: exerciseMap['restDuration'] as int? ?? 60,
                  );
                } catch (e) {
                  // Return a default exercise if parsing fails
                  return Exercise(
                    name: 'Push-Up',
                    targetMuscles: ['chest'],
                    load: ExerciseLoad(type: ExerciseLoadType.reps, sets: 1, reps: 10),
                    restDuration: 60,
                  );
                }
              }).toList(),
            );
            sessions.add(session);
          } catch (e) {
            log('WorkoutProgressTracker: Failed to create session', error: e);
          }
          currentExercises.clear();
        }

        // Start new session
        currentSession = <String, dynamic>{};
        currentSession['sessionName'] = line.substring(13).trim();
      } else if (currentSession != null) {
        // Parse session data
        if (line.startsWith('SESSION_TYPE:')) {
          currentSession['type'] = line.substring(13).trim();
        } else if (line.startsWith('DURATION:')) {
          currentSession['estimatedDuration'] = int.tryParse(line.substring(9).trim()) ?? 30;
        } else if (line.startsWith('EXERCISE:')) {
          if (currentExercise != null) {
            currentExercises.add(Map<String, dynamic>.from(currentExercise));
          }
          currentExercise = <String, dynamic>{};
          currentExercise['name'] = line.substring(9).trim();
        } else if (currentExercise != null) {
          // Parse exercise data
          if (line.startsWith('TARGET_MUSCLES:')) {
            final musclesText = line.substring(15).trim();
            currentExercise['targetMuscles'] = musclesText
                .split(',')
                .map((m) => m.trim())
                .where((m) => m.isNotEmpty)
                .toList();
          } else if (line.startsWith('LOAD_TYPE:')) {
            final loadType = line.substring(10).trim();
            currentExercise['load'] = <String, dynamic>{'type': loadType};
          } else if (line.startsWith('SETS:')) {
            final sets = int.tryParse(line.substring(5).trim()) ?? 1;
            final load = currentExercise['load'] as Map<String, dynamic>? ?? <String, dynamic>{};
            load['sets'] = sets;
            currentExercise['load'] = load;
          } else if (line.startsWith('REPS:')) {
            final repsText = line.substring(5).trim();
            if (repsText.isNotEmpty) {
              final reps = int.tryParse(repsText) ?? 1;
              final load = currentExercise['load'] as Map<String, dynamic>? ?? <String, dynamic>{};
              load['reps'] = reps;
              currentExercise['load'] = load;
            }
          } else if (line.startsWith('DURATION:')) {
            final durationText = line.substring(9).trim();
            if (durationText.isNotEmpty) {
              final duration = int.tryParse(durationText) ?? 30;
              final load = currentExercise['load'] as Map<String, dynamic>? ?? <String, dynamic>{};
              load['duration'] = duration;
              currentExercise['load'] = load;
            }
          } else if (line.startsWith('REST:')) {
            final rest = int.tryParse(line.substring(5).trim()) ?? 60;
            currentExercise['restDuration'] = rest;
          }
        }
      }
    }

    // Don't forget the last exercise if session ended without SESSION_END
    if (currentExercise != null) {
      currentExercises.add(Map<String, dynamic>.from(currentExercise));
    }
    if (currentSession != null && currentExercises.isNotEmpty) {
      // Create session with available exercises, even if SESSION_END wasn't reached
      currentSession['exercises'] = List<Map<String, dynamic>>.from(currentExercises);

      try {
        final session = WorkoutSession(
          sessionName: currentSession['sessionName'] as String? ?? 'Workout Session',
          type: currentSession['type'] as String? ?? 'strength',
          estimatedDuration: currentSession['estimatedDuration'] as int? ?? 30,
          exercises: currentExercises.map((exerciseMap) {
            try {
              return Exercise(
                name: exerciseMap['name'] as String? ?? 'Unknown Exercise',
                targetMuscles: List<String>.from(exerciseMap['targetMuscles'] as List? ?? []),
                load: ExerciseLoad(
                  type: ExerciseLoadType.fromString(exerciseMap['load']?['type'] as String? ?? 'reps'),
                  sets: exerciseMap['load']?['sets'] as int? ?? 1,
                  reps: exerciseMap['load']?['reps'] as int?,
                  duration: exerciseMap['load']?['duration'] as int?,
                ),
                restDuration: exerciseMap['restDuration'] as int? ?? 60,
              );
            } catch (e) {
              // Return a default exercise if parsing fails
              return Exercise(
                name: 'Push-Up',
                targetMuscles: ['chest'],
                load: ExerciseLoad(type: ExerciseLoadType.reps, sets: 1, reps: 10),
                restDuration: 60,
              );
            }
          }).toList(),
        );
        sessions.add(session);
      } catch (e) {
        log('WorkoutProgressTracker: Failed to create session', error: e);
      }
    }

    progress['Sessions'] = sessions;
    return progress;
  }

  bool _hasProgressChanged(Map<String, List<WorkoutSession>> newProgress) {
    if (newProgress.length != _currentProgress.length) return true;

    for (final entry in newProgress.entries) {
      final currentSessions = _currentProgress[entry.key];
      if (currentSessions == null ||
          currentSessions.length != entry.value.length ||
          !_sessionListEquals(currentSessions, entry.value)) {
        return true;
      }
    }

    return false;
  }

  bool _sessionListEquals(List<WorkoutSession> a, List<WorkoutSession> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].sessionName != b[i].sessionName || a[i].exercises.length != b[i].exercises.length) {
        return true;
      }
    }
    return false;
  }
}

/// Exception thrown when workout plan generation fails
class WorkoutPlanGenerationException implements Exception {
  final String message;
  final Exception? cause;

  WorkoutPlanGenerationException(this.message, [this.cause]);

  @override
  String toString() {
    if (cause != null) {
      return 'WorkoutPlanGenerationException: $message\nCaused by: $cause';
    }
    return 'WorkoutPlanGenerationException: $message';
  }
}
