import 'dart:developer' show log;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:waico/core/ai_models/chat_model.dart';
import 'package:waico/core/utils/map_utils.dart';
import 'package:waico/features/workout/models/workout_setup_data.dart';
import 'package:waico/features/workout/models/workout_plan.dart';
import 'package:waico/generated/locale_keys.g.dart';

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

  WorkoutPlanGenerator() {
    _chatModel = ChatModel(systemPrompt: LocaleKeys.workout_generation_system_prompt.tr());
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
      try {
        // Currently mediapipe's Gemma3n is in preview and only support 4096 tokens
        // I also noticed that it often generate malformed JSON when the schema is complex.
        // To simplify the schema, we ask Gemma to generate in Structured text and for one week only with essential informations
        // And we fill the rest of the data and weeks programmatically.

        final parsedPlan = _parseStructuredText(responseText);

        log('WorkoutPlanGenerator: Parsed workout plan:\n\n ############ \n\n $responseText\n\n############\n\n');

        // Add the programmatic data (weeks, sessions per week, etc.)
        parsedPlan["totalWeeks"] = 4;
        parsedPlan["workoutsPerWeek"] = setupData.selectedWeekDays.length;
        parsedPlan["weeklyPlans"] = [];

        final referencePlan = parsedPlan["plan"] as Map<String, dynamic>;

        // Create 4 weeks with progressive intensity
        for (int weekNumber = 1; weekNumber <= 4; weekNumber++) {
          final plan = referencePlan.deepCopy();
          plan["week"] = weekNumber;
          if (weekNumber > 2) {
            // Progressively increase exercise difficulty
            for (final session in plan["workoutSessions"] as List<dynamic>) {
              if (session is Map<String, dynamic>) {
                // Increase estimated duration by 10% for each week
                final estimatedDuration = session["estimatedDuration"] as int? ?? 0;
                session["estimatedDuration"] = (estimatedDuration + (estimatedDuration * 0.10 * weekNumber)).ceil();

                // Adjust exercises based on week
                final exercises = session["exercises"] as List<dynamic>?;
                if (exercises != null) {
                  for (final exercise in exercises) {
                    if (exercise is Map<String, dynamic>) {
                      // Increase reps or duration based on week
                      final load = exercise["load"] as Map<String, dynamic>?;
                      if (load != null) {
                        if (load["type"] == "reps") {
                          final reps = load["reps"] as int? ?? 12;
                          load["reps"] = (reps + (reps * 0.10 * weekNumber)).round();
                        } else if (load["type"] == "duration") {
                          final duration = load["duration"] as int? ?? 30;
                          load["duration"] = (duration + (duration * 0.10 * weekNumber)).round();
                        }
                      }
                      exercise["load"] = load;
                    }
                  }
                }
              }
            }
          }
          parsedPlan["weeklyPlans"].add(plan);
        }

        return WorkoutPlan.fromJson(parsedPlan);
      } catch (parseError, stackTrace) {
        log('WorkoutPlanGenerator: Text parsing failed', error: parseError, stackTrace: stackTrace);
        throw WorkoutPlanGenerationException(
          LocaleKeys.workout_generation_failed_to_parse.tr(),
          kDebugMode
              ? parseError is Exception
                    ? parseError
                    : Exception(parseError.toString())
              : null,
        );
      }
    } catch (e, stackTrace) {
      log('WorkoutPlanGenerator: Failed to generate workout plan', error: e, stackTrace: stackTrace);
      if (e is WorkoutPlanGenerationException) rethrow;

      throw WorkoutPlanGenerationException(
        LocaleKeys.workout_generation_failed_to_generate.tr(namedArgs: {'error': e.toString()}),
        e is Exception ? e : Exception(e.toString()),
      );
    } finally {
      await _chatModel.dispose();
    }
  }

  /// Builds a comprehensive prompt from user setup data
  String _buildPrompt(WorkoutSetupData setupData) {
    final buffer = StringBuffer();

    buffer.writeln(LocaleKeys.workout_generation_base_prompt.tr());
    buffer.writeln();

    // Physical stats
    buffer.writeln(LocaleKeys.workout_generation_physical_profile.tr());
    if (setupData.age != null) {
      buffer.writeln('- ${LocaleKeys.workout_generation_age_label.tr(namedArgs: {'age': setupData.age.toString()})}');
    }
    if (setupData.gender != null) {
      buffer.writeln('- ${LocaleKeys.workout_generation_gender_label.tr(namedArgs: {'gender': setupData.gender!})}');
    }
    if (setupData.weight != null) {
      buffer.writeln(
        '- ${LocaleKeys.workout_generation_weight_label.tr(namedArgs: {'weight': setupData.weight.toString()})}',
      );
    }
    if (setupData.height != null) {
      buffer.writeln(
        '- ${LocaleKeys.workout_generation_height_label.tr(namedArgs: {'height': setupData.height.toString()})}',
      );
    }
    if (setupData.bmi != null) {
      buffer.writeln(
        '- ${LocaleKeys.workout_generation_bmi_label.tr(namedArgs: {'bmi': setupData.bmi!.toStringAsFixed(1)})}',
      );
    }
    buffer.writeln();

    // Fitness level and experience
    buffer.writeln(LocaleKeys.workout_generation_fitness_background.tr());
    if (setupData.currentFitnessLevel != null) {
      buffer.writeln(
        '- ${LocaleKeys.workout_generation_current_fitness_level.tr(namedArgs: {'level': setupData.currentFitnessLevel!})}',
      );
    }
    if (setupData.experienceLevel != null) {
      buffer.writeln(
        '- ${LocaleKeys.workout_generation_exercise_experience.tr(namedArgs: {'experience': setupData.experienceLevel!})}',
      );
    }
    buffer.writeln(
      '- ${LocaleKeys.workout_generation_weekly_workout_frequency.tr(namedArgs: {'days': setupData.selectedWeekDays.join(', '), 'count': setupData.selectedWeekDays.length.toString()})}',
    );
    buffer.writeln(
      '- ${LocaleKeys.workout_generation_preferred_workout_duration.tr(namedArgs: {'duration': setupData.workoutDurationPreference.toString()})}',
    );
    buffer.writeln();

    // Goals and preferences
    buffer.writeln(LocaleKeys.workout_generation_goals_and_preferences.tr());
    if (setupData.primaryGoal != null) {
      buffer.writeln('- ${LocaleKeys.workout_generation_primary_goal.tr(namedArgs: {'goal': setupData.primaryGoal!})}');
    }
    if (setupData.targetWeight != null) {
      buffer.writeln(
        '- ${LocaleKeys.workout_generation_target_weight.tr(namedArgs: {'weight': setupData.targetWeight.toString()})}',
      );
    }
    // if (setupData.timeframe != null) {
    // buffer.writeln('- Timeframe: ${setupData.timeframe}');
    // TODO: Uncomment above when the full context of gemma3n is available in mediapipe
    // }
    // buffer.writeln('- Timeframe: 2 Weeks'); // Fixed to 2 weeks for now

    if (setupData.specificGoals.isNotEmpty) {
      buffer.writeln(
        '- ${LocaleKeys.workout_generation_specific_goals.tr(namedArgs: {'goals': setupData.specificGoals.join(", ")})}',
      );
    }

    buffer.writeln();

    buffer.writeln(LocaleKeys.workout_generation_plan_requirements_intro.tr());
    buffer.writeln(LocaleKeys.workout_generation_plan_requirement_1.tr());
    buffer.writeln(LocaleKeys.workout_generation_plan_requirement_2.tr());
    buffer.writeln(LocaleKeys.workout_generation_plan_requirement_3.tr());
    buffer.writeln(LocaleKeys.workout_generation_plan_requirement_4.tr());
    buffer.writeln(LocaleKeys.workout_generation_plan_requirement_5.tr());

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

      if (line.startsWith(LocaleKeys.workout_generation_keywords_plan_name.tr())) {
        result['planName'] = line.substring(LocaleKeys.workout_generation_keywords_plan_name.tr().length).trim();
      } else if (line.startsWith(LocaleKeys.workout_generation_keywords_description.tr())) {
        result['description'] = line.substring(LocaleKeys.workout_generation_keywords_description.tr().length).trim();
      } else if (line.startsWith(LocaleKeys.workout_generation_keywords_difficulty.tr())) {
        result['difficulty'] = line.substring(LocaleKeys.workout_generation_keywords_difficulty.tr().length).trim();
      } else if (line.startsWith(LocaleKeys.workout_generation_keywords_focus.tr())) {
        planFocus = line.substring(LocaleKeys.workout_generation_keywords_focus.tr().length).trim();
      } else if (line.startsWith(LocaleKeys.workout_generation_keywords_session_name.tr())) {
        // Save previous session if it exists
        if (currentSession != null) {
          // Add the current exercise if it exists
          if (currentExercise != null) {
            currentExercises.add(Map<String, dynamic>.from(currentExercise));
            currentExercise = null;
          }

          currentSession['exercises'] = currentExercises.map((e) => e.deepCopy()).toList();
          sessions.add(currentSession);
          currentExercises.clear();
        }

        // Start a new session
        currentSession = <String, dynamic>{};
        currentSession['sessionName'] = line
            .substring(LocaleKeys.workout_generation_keywords_session_name.tr().length)
            .trim();
      } else if (currentSession != null) {
        // Inside a session
        if (line.startsWith(LocaleKeys.workout_generation_keywords_session_type.tr())) {
          currentSession['type'] = line
              .substring(LocaleKeys.workout_generation_keywords_session_type.tr().length)
              .trim();
        } else if (line.startsWith(LocaleKeys.workout_generation_keywords_duration.tr()) && currentExercise == null) {
          // If currentExercise != null then the duration if for the exercise, not the session
          currentSession['estimatedDuration'] =
              int.tryParse(line.substring(LocaleKeys.workout_generation_keywords_duration.tr().length).trim()) ?? 30;
        } else if (line.startsWith(LocaleKeys.workout_generation_keywords_exercise.tr())) {
          // Save previous exercise if exists
          if (currentExercise != null) {
            currentExercises.add(Map<String, dynamic>.from(currentExercise));
          }
          // Start new exercise
          currentExercise = <String, dynamic>{};
          currentExercise['name'] = line.substring(LocaleKeys.workout_generation_keywords_exercise.tr().length).trim();
        } else if (currentExercise != null) {
          // Inside an exercise
          if (line.startsWith(LocaleKeys.workout_generation_keywords_target_muscles.tr())) {
            final musclesText = line
                .substring(LocaleKeys.workout_generation_keywords_target_muscles.tr().length)
                .trim();
            currentExercise['targetMuscles'] = musclesText
                .split(',')
                .map((m) => m.trim())
                .where((m) => m.isNotEmpty)
                .toList();
          } else if (line.startsWith(LocaleKeys.workout_generation_keywords_load_type.tr())) {
            final loadType = line.substring(LocaleKeys.workout_generation_keywords_load_type.tr().length).trim();
            currentExercise['load'] = <String, dynamic>{'type': loadType};
          } else if (line.startsWith(LocaleKeys.workout_generation_keywords_sets.tr())) {
            final setsText = line.substring(LocaleKeys.workout_generation_keywords_sets.tr().length).trim();
            // Remove any non-numeric characters (e.g., "sets")
            final cleanSetsText = _cleanNumber(setsText).trim();
            final sets = int.tryParse(cleanSetsText) ?? 1;
            final load = currentExercise['load'] as Map<String, dynamic>? ?? <String, dynamic>{};
            load['sets'] = sets;
            currentExercise['load'] = load;
          } else if (line.startsWith(LocaleKeys.workout_generation_keywords_reps.tr())) {
            final repsText = line.substring(LocaleKeys.workout_generation_keywords_reps.tr().length);
            // Remove any non-numeric characters (e.g., "reps")
            final cleanRepsText = _cleanNumber(repsText).trim();
            if (cleanRepsText.isNotEmpty) {
              final reps = int.tryParse(cleanRepsText) ?? 1;
              final load = currentExercise['load'] as Map<String, dynamic>? ?? <String, dynamic>{};
              load['reps'] = reps;
              currentExercise['load'] = load;
            }
          } else if (line.startsWith(LocaleKeys.workout_generation_keywords_duration.tr())) {
            final durationText = line.substring(LocaleKeys.workout_generation_keywords_duration.tr().length);
            // Remove any non-numeric characters (e.g., "seconds")
            final cleanDurationText = _cleanNumber(durationText).trim();
            if (cleanDurationText.isNotEmpty) {
              final duration = int.tryParse(cleanDurationText) ?? 30;
              final load = currentExercise['load'] as Map<String, dynamic>? ?? <String, dynamic>{};
              load['duration'] = duration;
              currentExercise['load'] = load;
            }
          } else if (line.startsWith(LocaleKeys.workout_generation_keywords_rest.tr())) {
            final restText = line.substring(LocaleKeys.workout_generation_keywords_rest.tr().length);
            // Remove any non-numeric characters (e.g., "seconds")
            final cleanRestText = _cleanNumber(restText).trim();
            final rest = int.tryParse(cleanRestText) ?? 60;
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

    // Add exercise image and instruction if available
    for (final session in sessions) {
      final exercises = session['exercises'] as List<Map<String, dynamic>>?;
      if (exercises != null) {
        for (final exercise in exercises) {
          final exerciseName = exercise['name'] as String? ?? '';
          final guide = _getExerciseGuide(exerciseName);
          if (guide != null) {
            exercise.addAll(guide);
          }
          final exerciseNameLower = exerciseName.toLowerCase();
          if (exerciseNameLower.contains('lunges') || exerciseNameLower.contains('lunge ')) {
            // Lunges and Split Squats are similar exercises, so sometimes the E2B variants
            // of Gemma3n will generate Lunges instead of Split Squats, although the prompt
            // only listed Split Squats in the allowed exercises.
            if (exerciseNameLower.contains('right')) {
              exercise['name'] = 'Split Squat (Right)';
            } else if (exerciseNameLower.contains('left')) {
              exercise['name'] = 'Split Squat (Left)';
            }
          }
        }
      }
    }

    // Build the plan structure
    result['plan'] = {'focus': planFocus ?? 'General fitness', 'workoutSessions': sessions};

    return result;
  }

  String _cleanNumber(String text) {
    // Remove any non-numeric characters (e.g., "sets", "reps", "seconds")
    return RegExp(r'\d+').firstMatch(text)?.group(0) ?? '';
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

      if (line.startsWith(LocaleKeys.workout_generation_keywords_session_name.tr())) {
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
                  final exerciseName = exerciseMap['name'] as String? ?? 'Unknown Exercise';
                  final guide = _getExerciseGuide(exerciseName);
                  return Exercise(
                    name: exerciseName,
                    targetMuscles: List<String>.from(exerciseMap['targetMuscles'] as List? ?? []),
                    load: ExerciseLoad(
                      type: ExerciseLoadType.fromString(exerciseMap['load']?['type'] as String? ?? 'reps'),
                      sets: exerciseMap['load']?['sets'] as int? ?? 1,
                      reps: exerciseMap['load']?['reps'] as int?,
                      duration: exerciseMap['load']?['duration'] as int?,
                    ),
                    restDuration: exerciseMap['restDuration'] as int? ?? 60,
                    image: guide?['image'],
                    instruction: guide?['instruction'],
                    optimalView: guide?['optimalView'],
                  );
                } catch (e) {
                  // Return a default exercise if parsing fails
                  final guide = _getExerciseGuide('Push-Up');
                  return Exercise(
                    name: 'Push-Up',
                    targetMuscles: ['chest'],
                    load: ExerciseLoad(type: ExerciseLoadType.reps, sets: 1, reps: 10),
                    restDuration: 60,
                    image: guide?['image'],
                    instruction: guide?['instruction'],
                    optimalView: guide?['optimalView'],
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
        currentSession['sessionName'] = line
            .substring(LocaleKeys.workout_generation_keywords_session_name.tr().length)
            .trim();
      } else if (currentSession != null) {
        // Parse session data
        if (line.startsWith(LocaleKeys.workout_generation_keywords_session_type.tr())) {
          currentSession['type'] = line
              .substring(LocaleKeys.workout_generation_keywords_session_type.tr().length)
              .trim();
        } else if (line.startsWith(LocaleKeys.workout_generation_keywords_duration.tr()) && currentExercise == null) {
          // If currentExercise != null then the duration if for the exercise, not the session
          currentSession['estimatedDuration'] =
              int.tryParse(line.substring(LocaleKeys.workout_generation_keywords_duration.tr().length).trim()) ?? 30;
        } else if (line.startsWith(LocaleKeys.workout_generation_keywords_exercise.tr())) {
          if (currentExercise != null) {
            currentExercises.add(Map<String, dynamic>.from(currentExercise));
          }
          currentExercise = <String, dynamic>{};
          currentExercise['name'] = line.substring(LocaleKeys.workout_generation_keywords_exercise.tr().length).trim();
        } else if (currentExercise != null) {
          // Parse exercise data
          if (line.startsWith(LocaleKeys.workout_generation_keywords_target_muscles.tr())) {
            final musclesText = line
                .substring(LocaleKeys.workout_generation_keywords_target_muscles.tr().length)
                .trim();
            currentExercise['targetMuscles'] = musclesText
                .split(',')
                .map((m) => m.trim())
                .where((m) => m.isNotEmpty)
                .toList();
          } else if (line.startsWith(LocaleKeys.workout_generation_keywords_load_type.tr())) {
            final loadType = line.substring(LocaleKeys.workout_generation_keywords_load_type.tr().length).trim();
            currentExercise['load'] = <String, dynamic>{'type': loadType};
          } else if (line.startsWith(LocaleKeys.workout_generation_keywords_sets.tr())) {
            final sets =
                int.tryParse(line.substring(LocaleKeys.workout_generation_keywords_sets.tr().length).trim()) ?? 1;
            final load = currentExercise['load'] as Map<String, dynamic>? ?? <String, dynamic>{};
            load['sets'] = sets;
            currentExercise['load'] = load;
          } else if (line.startsWith(LocaleKeys.workout_generation_keywords_reps.tr())) {
            final repsText = line.substring(LocaleKeys.workout_generation_keywords_reps.tr().length).trim();
            if (repsText.isNotEmpty) {
              final reps = int.tryParse(repsText) ?? 1;
              final load = currentExercise['load'] as Map<String, dynamic>? ?? <String, dynamic>{};
              load['reps'] = reps;
              currentExercise['load'] = load;
            }
          } else if (line.startsWith(LocaleKeys.workout_generation_keywords_duration.tr())) {
            final durationText = line.substring(LocaleKeys.workout_generation_keywords_duration.tr().length).trim();
            if (durationText.isNotEmpty) {
              final duration = int.tryParse(durationText) ?? 30;
              final load = currentExercise['load'] as Map<String, dynamic>? ?? <String, dynamic>{};
              load['duration'] = duration;
              currentExercise['load'] = load;
            }
          } else if (line.startsWith(LocaleKeys.workout_generation_keywords_rest.tr())) {
            final rest =
                int.tryParse(line.substring(LocaleKeys.workout_generation_keywords_rest.tr().length).trim()) ?? 60;
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
              final exerciseName = exerciseMap['name'] as String? ?? 'Unknown Exercise';
              final guide = _getExerciseGuide(exerciseName);
              return Exercise(
                name: exerciseName,
                targetMuscles: List<String>.from(exerciseMap['targetMuscles'] as List? ?? []),
                load: ExerciseLoad(
                  type: ExerciseLoadType.fromString(exerciseMap['load']?['type'] as String? ?? 'reps'),
                  sets: exerciseMap['load']?['sets'] as int? ?? 1,
                  reps: exerciseMap['load']?['reps'] as int?,
                  duration: exerciseMap['load']?['duration'] as int?,
                ),
                restDuration: exerciseMap['restDuration'] as int? ?? 60,
                image: guide?['image'],
                instruction: guide?['instruction'],
                optimalView: guide?['optimalView'],
              );
            } catch (e) {
              // Return a default exercise if parsing fails
              final guide = _getExerciseGuide('Push-Up');
              return Exercise(
                name: 'Push-Up',
                targetMuscles: ['chest'],
                load: ExerciseLoad(type: ExerciseLoadType.reps, sets: 1, reps: 10),
                restDuration: 60,
                image: guide?['image'],
                instruction: guide?['instruction'],
                optimalView: guide?['optimalView'],
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

/// Get exercise guide data based on exercise name using intelligent parsing
Map<String, String>? _getExerciseGuide(String exerciseName) {
  final lowerName = exerciseName.toLowerCase();
  final exerciseGuideMap = _getExerciseGuideMap();

  // Use intelligent parsing similar to WorkoutSessionManager
  if (lowerName.contains('push') && lowerName.contains('up')) {
    if (lowerName.contains('knee')) {
      return exerciseGuideMap['knee_push_up'];
    } else if (lowerName.contains('wall')) {
      return exerciseGuideMap['wall_pushup'];
    } else if (lowerName.contains('incline')) {
      return exerciseGuideMap['incline_push_up'];
    } else if (lowerName.contains('decline')) {
      return exerciseGuideMap['decline_push_up'];
    } else if (lowerName.contains('diamond') || lowerName.contains('close')) {
      return exerciseGuideMap['close_push_up'];
    } else if (lowerName.contains('wide')) {
      return exerciseGuideMap['push_up']; // Use standard push-up for now
    } else {
      return exerciseGuideMap['push_up'];
    }
  } else if (lowerName.contains('squat')) {
    if (lowerName.contains('sumo')) {
      return exerciseGuideMap['sumo_squat'];
    } else if (lowerName.contains('split')) {
      return exerciseGuideMap['split_squat'];
    } else {
      return exerciseGuideMap['squat'];
    }
  } else if (lowerName.contains('crunch')) {
    if (lowerName.contains('reverse')) {
      return exerciseGuideMap['reverse_crunch'];
    } else if (lowerName.contains('double')) {
      return exerciseGuideMap['double_crunch'];
    } else {
      return exerciseGuideMap['crunch'];
    }
  } else if (lowerName.contains('superman')) {
    return exerciseGuideMap['superman'];
  } else if (lowerName.contains('plank')) {
    if (lowerName.contains('side')) {
      return exerciseGuideMap['side_plank'];
    } else {
      return exerciseGuideMap['plank'];
    }
  } else if (lowerName.contains('jumping') && lowerName.contains('jack')) {
    return exerciseGuideMap['jumping_jacks'];
  } else if (lowerName.contains('high') && lowerName.contains('knee')) {
    return exerciseGuideMap['high_knee'];
  } else if (lowerName.contains('mountain') && lowerName.contains('climber')) {
    return exerciseGuideMap['mountain_climbers'];
  } else if (lowerName.contains('wall') && lowerName.contains('sit')) {
    return exerciseGuideMap['wall_sit'];
  }

  // Fallback: try exact normalized matching
  final normalizedName = exerciseName
      .toLowerCase()
      .replaceAll(' ', '_')
      .replaceAll('-', '_')
      .replaceAll('(', '')
      .replaceAll(')', '');

  return exerciseGuideMap[normalizedName];
}

/// Exercise guide map with images and instructions
Map<String, Map<String, String>> _getExerciseGuideMap() => {
  "close_push_up": {
    "image": "assets/images/exercises/close_puch_up.gif",
    "optimalView": "side",
    "instruction": LocaleKeys.workout_generation_exercise_instructions_close_push_up.tr(),
  },
  "crunch": {
    "image": "assets/images/exercises/crunch.gif",
    "optimalView": "side",
    "instruction": LocaleKeys.workout_generation_exercise_instructions_crunch.tr(),
  },
  "decline_push_up": {
    "image": "assets/images/exercises/decline_push_up.gif",
    "optimalView": "side",
    "instruction": LocaleKeys.workout_generation_exercise_instructions_decline_push_up.tr(),
  },
  "double_crunch": {
    "image": "assets/images/exercises/duble_crunch.gif",
    "optimalView": "side",
    "instruction": LocaleKeys.workout_generation_exercise_instructions_double_crunch.tr(),
  },
  "high_knee": {
    "image": "assets/images/exercises/high_knee.gif",
    "optimalView": "side",
    "instruction": LocaleKeys.workout_generation_exercise_instructions_high_knee.tr(),
  },
  "incline_push_up": {
    "image": "assets/images/exercises/incline_push_up.gif",
    "optimalView": "side",
    "instruction": LocaleKeys.workout_generation_exercise_instructions_incline_push_up.tr(),
  },
  "jumping_jacks": {
    "image": "assets/images/exercises/jumping_jacks.gif",
    "optimalView": "front",
    "instruction": LocaleKeys.workout_generation_exercise_instructions_jumping_jacks.tr(),
  },
  "knee_push_up": {
    "image": "assets/images/exercises/knee_push_up.gif",
    "optimalView": "side",
    "instruction": LocaleKeys.workout_generation_exercise_instructions_knee_push_up.tr(),
  },
  "mountain_climbers": {
    "image": "assets/images/exercises/mountain_climbers.webp",
    "optimalView": "side",
    "instruction": LocaleKeys.workout_generation_exercise_instructions_mountain_climbers.tr(),
  },
  "plank": {
    "image": "assets/images/exercises/plank.webp",
    "optimalView": "side",
    "instruction": LocaleKeys.workout_generation_exercise_instructions_plank.tr(),
  },
  "push_up": {
    "image": "assets/images/exercises/push_up.gif",
    "optimalView": "side",
    "instruction": LocaleKeys.workout_generation_exercise_instructions_push_up.tr(),
  },
  "reverse_crunch": {
    "image": "assets/images/exercises/reverse_crunch.gif",
    "optimalView": "side",
    "instruction": LocaleKeys.workout_generation_exercise_instructions_reverse_crunch.tr(),
  },
  "side_plank": {
    "image": "assets/images/exercises/side_plank.png",
    "optimalView": "side",
    "instruction": LocaleKeys.workout_generation_exercise_instructions_side_plank.tr(),
  },
  "split_squat": {
    "image": "assets/images/exercises/split_squat.gif",
    "optimalView": "side",
    "instruction": LocaleKeys.workout_generation_exercise_instructions_split_squat.tr(),
  },
  "squat": {
    "image": "assets/images/exercises/squat.gif",
    "optimalView": "side",
    "instruction": LocaleKeys.workout_generation_exercise_instructions_squat.tr(),
  },
  "sumo_squat": {
    "image": "assets/images/exercises/sumo_squat.gif",
    "optimalView": "front",
    "instruction": LocaleKeys.workout_generation_exercise_instructions_sumo_squat.tr(),
  },
  "superman": {
    "image": "assets/images/exercises/superman.gif",
    "optimalView": "side",
    "instruction": LocaleKeys.workout_generation_exercise_instructions_superman.tr(),
  },
  "wall_pushup": {
    "image": "assets/images/exercises/wall_pushup.webp",
    "optimalView": "side",
    "instruction": LocaleKeys.workout_generation_exercise_instructions_wall_pushup.tr(),
  },
  "wall_sit": {
    "image": "assets/images/exercises/wall_sit.jpg.webp",
    "optimalView": "side",
    "instruction": LocaleKeys.workout_generation_exercise_instructions_wall_sit.tr(),
  },
};
