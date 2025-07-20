import 'dart:convert';

/// Tracks the completion status of exercises in a workout plan
class WorkoutProgress {
  final Map<String, bool> exerciseCompletions;
  final DateTime lastUpdated;

  const WorkoutProgress({required this.exerciseCompletions, required this.lastUpdated});

  factory WorkoutProgress.empty() {
    return WorkoutProgress(exerciseCompletions: {}, lastUpdated: DateTime.now());
  }

  factory WorkoutProgress.fromJson(Map<String, dynamic> json) {
    return WorkoutProgress(
      exerciseCompletions: Map<String, bool>.from(json['exerciseCompletions'] ?? {}),
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {'exerciseCompletions': exerciseCompletions, 'lastUpdated': lastUpdated.toIso8601String()};
  }

  factory WorkoutProgress.fromJsonString(String jsonString) {
    return WorkoutProgress.fromJson(json.decode(jsonString));
  }

  String toJsonString() {
    return json.encode(toJson());
  }

  /// Creates a new WorkoutProgress with an exercise completion toggled (The returned progress will have the completion status opposite of the current status)
  WorkoutProgress withExerciseToggled(String exerciseKey) {
    final newCompletions = Map<String, bool>.from(exerciseCompletions);
    newCompletions[exerciseKey] = !(newCompletions[exerciseKey] ?? false);

    return WorkoutProgress(exerciseCompletions: newCompletions, lastUpdated: DateTime.now());
  }

  /// Creates a new WorkoutProgress with an exercise completion set
  WorkoutProgress withExerciseCompleted(String exerciseKey, bool completed) {
    final newCompletions = Map<String, bool>.from(exerciseCompletions);
    newCompletions[exerciseKey] = completed;

    return WorkoutProgress(exerciseCompletions: newCompletions, lastUpdated: DateTime.now());
  }

  /// Checks if an exercise is completed
  bool isExerciseCompleted(String exerciseKey) {
    return exerciseCompletions[exerciseKey] ?? false;
  }

  /// Generates the exercise key for tracking
  static String getExerciseKey(int week, int sessionIndex, int exerciseIndex) {
    return 'w${week}_s${sessionIndex}_e$exerciseIndex';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is WorkoutProgress &&
        other.exerciseCompletions == exerciseCompletions &&
        other.lastUpdated == lastUpdated;
  }

  @override
  int get hashCode => exerciseCompletions.hashCode ^ lastUpdated.hashCode;
}
