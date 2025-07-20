import 'dart:convert';
import 'dart:developer' show log;

import 'package:waico/core/ai_models/chat_model.dart';
import 'package:waico/features/workout/models/workout_setup_data.dart';
import 'package:waico/features/workout/models/workout_plan.dart';

/// Generates personalized workout plans using AI based on user setup data
class WorkoutPlanGenerator {
  late final ChatModel _chatModel;

  static const String _systemPrompt = r'''
You are an expert personal trainer and exercise physiologist with over 15 years of experience designing customized workout programs. You specialize in creating safe, effective, and sustainable bodyweight workout plans tailored to individual goals, and workout experience levels.

Your expertise includes:
- Exercise physiology and biomechanics
- Progressive overload principles
- Adaptation strategies for different fitness levels (beginner, intermediate, advanced)

Progressive Overload Guidelines:
- Week 1-2: Focus on form and adaptation
- Week 3-4: Increase intensity/volume by 5-10%

Safety Considerations:
- Provide rest periods appropriate for exercise intensity
- Emphasize proper form over heavy weights for beginners

Make sure to chose exercise variations that are suitable for the user's fitness level and experience. For example, for Push up exercises, prefer "Knee Push-Up" and "Wall Push-Up" for beginners.

**JSON Schema Requirements**:
```json
{
  "type": "object",
  "properties": {
    "planName": {
      "type": "string",
      "description": "A short, motivating, yet descriptive name for the workout plan based on the user's goal"
    },
    "description": {
      "type": "string",
      "description": "Brief overview of the plan's approach and benefits (2-3 sentences)"
    },
    "totalWeeks": {
      "type": "integer",
      "description": "Number of weeks the plan spans (typically 4-12 weeks)"
    },
    "workoutsPerWeek": {
      "type": "integer",
      "description": "Number of workout sessions per week"
    },
    "weeklyPlans": {
      "type": "array",
      "description": "Array of weekly workout plans with progressive difficulty",
      "items": {
        "type": "object",
        "properties": {
          "week": { "type": "integer", "description": "Week number" },
          "focus": { "type": "string", "description": "Main focus for this week" },
          "workoutSessions": {
            "type": "array",
            "items": {
              "type": "object",
              "properties": {
                "sessionName": { "type": "string" },
                "type": { "type": "string" },
                "estimatedDuration": { "type": "integer", "description": "Duration in minutes" },
                "exercises": {
                  "type": "array",
                  "items": { 
                    "type": "object",
                    "properties": {
                      "name": { 
                        "type": "string", 
                        "enum": [
                          "Push-Up", "Knee Push-Up", "Wall Push-Up", "Incline Push-Up", 
                          "Decline Push-Up", "Diamond Push-Up", "Wide Push-Up",
                          "Squat", "Sumo Squat", "Split Squat (Right)", "Split Squat (Left)",
                          "Crunch", "Reverse Crunch", "Double Crunch",
                          "Superman", "Superman Pulse", "Y Superman", 
                          "Wall Sit", "Plank", "Side Plank", "Jumping Jacks", "High Knees", "Burpees", "Mountain Climbers"
                        ],
                      },
                      "category": {
                        "type": "string",
                        "enum": ["push_up", "squat", "crunch", "superman", "endurance", "cardio"],
                        "description": "Category of the exercise. example: cardio for Jumping Jacks, High Knees, Burpees, Mountain Climbers; endurance for Plank, Side Plank, Wall Sit; push_up for all push-up variations; squat for all squat variations; crunch for all crunch variations; superman for all superman variations"
                      },
                      "targetMuscles": {
                        "type": "array",
                        "items": { "type": "string" }
                      },
                      "load": {
                        "type": "object",
                        "properties": {
                          "type": {
                            "type": "string",
                            "enum": ["reps", "duration"],
                            "description": "Use 'reps' for reps-based exercise categories (push_up, squat, crunch, superman) and 'duration' for duration-based categories (endurance, cardio)"
                          },
                          "sets": { "type": "integer" },
                          "reps": { "type": "integer", "description": "Required for reps-based exercises" },
                          "duration": { "type": "integer", "description": "Duration in seconds for duration-based exercises" },
                        }
                      },
                      "restPeriod": { "type": "integer", "description": "Rest period in seconds" },
                    },
                  }
                },
              },
            }
          }
        },
      }
    },
    "difficulty": {
      "type": "string",
      "enum": ["Beginner", "Intermediate", "Advanced"],
      "description": "Overall difficulty level"
    },
    "targetMuscleGroups": {
      "type": "array",
      "items": { "type": "string" },
      "description": "Array of primary muscle groups targeted"
    }
  },
}
```
"Split Squat (Right)" and "Split Squat (Left)" must always follow each other they should not be used separately or have another exercise in between them.

Remember: Your response must be ONLY valid JSON that can be parsed directly into a WorkoutPlan object.
''';

  WorkoutPlanGenerator() {
    _chatModel = ChatModel(systemPrompt: _systemPrompt);
  }

  /// Generates a personalized workout plan based on the provided setup data
  ///
  /// Takes [WorkoutSetupData] containing user preferences, goals, and constraints
  /// Returns a [WorkoutPlan] with a structured, progressive workout program
  ///
  /// Throws [WorkoutPlanGenerationException] if plan generation fails
  Future<WorkoutPlan> generate(WorkoutSetupData setupData) async {
    try {
      await _chatModel.initialize();

      final prompt = _buildPrompt(setupData);
      log('WorkoutPlanGenerator: Generating workout plan for user with goals: ${setupData.primaryGoal}');

      final response = StringBuffer();
      await for (final chunk in _chatModel.sendMessageStream(prompt)) {
        response.write(chunk);
      }

      final responseText = response.toString().trim();
      log('WorkoutPlanGenerator: Received response of length: ${responseText.length}');

      // Try to extract JSON if it's wrapped in markdown code blocks
      final jsonText = _extractJson(responseText);

      try {
        final jsonData = json.decode(jsonText);
        return WorkoutPlan.fromJson(jsonData);
      } catch (parseError) {
        log('WorkoutPlanGenerator: JSON parsing failed', error: parseError);
        throw WorkoutPlanGenerationException(
          'Failed to parse workout plan JSON response',
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
    buffer.writeln('**Physical Profile:**');
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
    buffer.writeln('- Weekly workout frequency: ${setupData.weeklyWorkoutFrequency} sessions');
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
    if (setupData.timeframe != null) {
      buffer.writeln('- Timeframe: ${setupData.timeframe}');
    }

    if (setupData.specificGoals.isNotEmpty) {
      buffer.writeln('- Specific goals: ${setupData.specificGoals.join(", ")}');
    }

    if (setupData.preferredWorkoutTypes.isNotEmpty) {
      buffer.writeln('- Preferred workout types: ${setupData.preferredWorkoutTypes.join(", ")}');
    }
    buffer.writeln();

    buffer.writeln('Please generate a comprehensive workout plan that:');
    buffer.writeln('1. Matches the user\'s fitness level and experience');
    buffer.writeln('2. Aligns with their specific goals and preferences');
    buffer.writeln('3. Fits within their time constraints');

    return buffer.toString();
  }

  /// Extracts JSON from response text, handling markdown code blocks
  String _extractJson(String responseText) {
    // Try to extract JSON from markdown code blocks first
    final jsonMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', multiLine: true).firstMatch(responseText);
    if (jsonMatch != null) {
      return jsonMatch.group(1)?.trim() ?? responseText.trim();
    }

    // If no code blocks found, try to find JSON object boundaries
    final startIndex = responseText.indexOf('{');
    final lastIndex = responseText.lastIndexOf('}');

    if (startIndex != -1 && lastIndex != -1 && lastIndex > startIndex) {
      return responseText.substring(startIndex, lastIndex + 1);
    }

    // Return the original text if no JSON structure is detected
    return responseText.trim();
  }

  /// Disposes of the chat model resources
  Future<void> dispose() async {
    await _chatModel.dispose();
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
