import 'package:flutter_test/flutter_test.dart';
import 'package:waico/features/workout/workout_plan_generator.dart';
import 'dart:convert';

void main() {
  test('debug parse result', () {
    final generator = WorkoutPlanGenerator();

    const sampleText = '''
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
SETS: 3
REPS: 12
DURATION: 
REST: 60

EXERCISE: Plank
TARGET_MUSCLES: core, shoulders
LOAD_TYPE: duration
SETS: 3
REPS: 
DURATION: 30
REST: 45
''';

    final result = generator.parseStructuredText(sampleText);
    print('Parse result: ${JsonEncoder.withIndent('  ').convert(result)}');

    // Test that we can create a plan structure
    expect(result['planName'], isNotNull);
    expect(result['plan'], isNotNull);

    final plan = result['plan'] as Map<String, dynamic>;
    expect(plan['workoutSessions'], isNotNull);

    final sessions = plan['workoutSessions'] as List<dynamic>;
    print('Number of sessions: ${sessions.length}');

    if (sessions.isNotEmpty) {
      final firstSession = sessions[0] as Map<String, dynamic>;
      print('First session: ${JsonEncoder.withIndent('  ').convert(firstSession)}');

      final exercises = firstSession['exercises'] as List<dynamic>?;
      if (exercises != null) {
        print('Number of exercises: ${exercises.length}');
        for (int i = 0; i < exercises.length; i++) {
          print('Exercise $i: ${JsonEncoder.withIndent('  ').convert(exercises[i])}');
        }
      }
    }
  });
}
