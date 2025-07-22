import 'package:flutter_test/flutter_test.dart';
import 'package:waico/features/workout/workout_plan_generator.dart';

void main() {
  group('WorkoutPlanGenerator', () {
    late WorkoutPlanGenerator generator;

    setUp(() {
      generator = WorkoutPlanGenerator();
    });

    test('should parse structured text format correctly', () {
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

      // Test the parsing method
      final result = generator.parseStructuredText(sampleText);

      expect(result['planName'], equals('Full Body Strength Builder'));
      expect(result['description'], contains('comprehensive bodyweight program'));
      expect(result['difficulty'], equals('Intermediate'));

      final plan = result['plan'] as Map<String, dynamic>;
      expect(plan['focus'], equals('Foundation building and strength development'));

      final sessions = plan['workoutSessions'] as List<dynamic>;
      expect(sessions.length, equals(2));

      final firstSession = sessions[0] as Map<String, dynamic>;
      expect(firstSession['sessionName'], equals('Monday - Upper Body'));
      expect(firstSession['type'], equals('strength'));
      expect(firstSession['estimatedDuration'], equals(30));

      final exercises = firstSession['exercises'] as List<dynamic>;
      expect(exercises.length, equals(2));

      final pushUp = exercises[0] as Map<String, dynamic>;
      expect(pushUp['name'], equals('Push-Up'));
      expect(pushUp['targetMuscles'], equals(['chest', 'shoulders', 'triceps']));
      expect(pushUp['restDuration'], equals(60));

      final load = pushUp['load'] as Map<String, dynamic>;
      expect(load['type'], equals('reps'));
      expect(load['sets'], equals(3));
      expect(load['reps'], equals(12));
    });

    tearDown(() async {
      await generator.dispose();
    });
  });
}
