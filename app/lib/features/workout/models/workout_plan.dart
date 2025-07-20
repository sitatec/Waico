import 'dart:convert';

class WorkoutPlan {
  final String planName;
  final String description;
  final int totalWeeks;
  final int workoutsPerWeek;
  final List<WeeklyPlan> weeklyPlans;
  final String difficulty;
  final List<String> targetMuscleGroups;

  const WorkoutPlan({
    required this.planName,
    required this.description,
    required this.totalWeeks,
    required this.workoutsPerWeek,
    required this.weeklyPlans,
    required this.difficulty,
    required this.targetMuscleGroups,
  });

  factory WorkoutPlan.fromJson(Map<String, dynamic> json) {
    return WorkoutPlan(
      planName: json['planName'] as String,
      description: json['description'] as String,
      totalWeeks: json['totalWeeks'] as int,
      workoutsPerWeek: json['workoutsPerWeek'] as int,
      weeklyPlans: (json['weeklyPlans'] as List<dynamic>)
          .map((e) => WeeklyPlan.fromJson(e as Map<String, dynamic>))
          .toList(),
      difficulty: json['difficulty'] as String,
      targetMuscleGroups: List<String>.from(json['targetMuscleGroups'] as List),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'planName': planName,
      'description': description,
      'totalWeeks': totalWeeks,
      'workoutsPerWeek': workoutsPerWeek,
      'weeklyPlans': weeklyPlans.map((e) => e.toJson()).toList(),
      'difficulty': difficulty,
      'targetMuscleGroups': targetMuscleGroups,
    };
  }

  factory WorkoutPlan.fromJsonString(String jsonString) {
    return WorkoutPlan.fromJson(json.decode(jsonString));
  }

  String toJsonString() {
    return json.encode(toJson());
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is WorkoutPlan &&
        other.planName == planName &&
        other.description == description &&
        other.totalWeeks == totalWeeks &&
        other.workoutsPerWeek == workoutsPerWeek &&
        other.weeklyPlans == weeklyPlans &&
        other.difficulty == difficulty &&
        other.targetMuscleGroups == targetMuscleGroups;
  }

  @override
  int get hashCode {
    return planName.hashCode ^
        description.hashCode ^
        totalWeeks.hashCode ^
        workoutsPerWeek.hashCode ^
        weeklyPlans.hashCode ^
        difficulty.hashCode ^
        targetMuscleGroups.hashCode;
  }
}

class WeeklyPlan {
  final int week;
  final String focus;
  final List<WorkoutSession> workoutSessions;

  const WeeklyPlan({required this.week, required this.focus, required this.workoutSessions});

  factory WeeklyPlan.fromJson(Map<String, dynamic> json) {
    return WeeklyPlan(
      week: json['week'] as int,
      focus: json['focus'] as String,
      workoutSessions: (json['workoutSessions'] as List<dynamic>)
          .map((e) => WorkoutSession.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'week': week, 'focus': focus, 'workoutSessions': workoutSessions.map((e) => e.toJson()).toList()};
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is WeeklyPlan &&
        other.week == week &&
        other.focus == focus &&
        other.workoutSessions == workoutSessions;
  }

  @override
  int get hashCode {
    return week.hashCode ^ focus.hashCode ^ workoutSessions.hashCode;
  }
}

class WorkoutSession {
  final String sessionName;
  final String type;
  final int estimatedDuration; // in minutes
  final List<Exercise> exercises;

  const WorkoutSession({
    required this.sessionName,
    required this.type,
    required this.estimatedDuration,
    required this.exercises,
  });

  factory WorkoutSession.fromJson(Map<String, dynamic> json) {
    return WorkoutSession(
      sessionName: json['sessionName'] as String,
      type: json['type'] as String,
      estimatedDuration: json['estimatedDuration'] as int,
      exercises: (json['exercises'] as List<dynamic>).map((e) => Exercise.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sessionName': sessionName,
      'type': type,
      'estimatedDuration': estimatedDuration,
      'exercises': exercises.map((e) => e.toJson()).toList(),
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is WorkoutSession &&
        other.sessionName == sessionName &&
        other.type == type &&
        other.estimatedDuration == estimatedDuration &&
        other.exercises == exercises;
  }

  @override
  int get hashCode {
    return sessionName.hashCode ^ type.hashCode ^ estimatedDuration.hashCode ^ exercises.hashCode;
  }
}

class Exercise {
  final String name;
  final String category;
  final List<String> targetMuscles;
  final ExerciseLoad load;
  final int restPeriod; // in seconds

  const Exercise({
    required this.name,
    required this.category,
    required this.targetMuscles,
    required this.load,
    required this.restPeriod,
  });

  factory Exercise.fromJson(Map<String, dynamic> json) {
    return Exercise(
      name: json['name'] as String,
      category: json['category'] as String,
      targetMuscles: List<String>.from(json['targetMuscles'] as List),
      load: ExerciseLoad.fromJson(json['load'] as Map<String, dynamic>),
      restPeriod: json['restPeriod'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'category': category,
      'targetMuscles': targetMuscles,
      'load': load.toJson(),
      'restPeriod': restPeriod,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Exercise &&
        other.name == name &&
        other.category == category &&
        other.targetMuscles == targetMuscles &&
        other.load == load &&
        other.restPeriod == restPeriod;
  }

  @override
  int get hashCode {
    return name.hashCode ^ category.hashCode ^ targetMuscles.hashCode ^ load.hashCode ^ restPeriod.hashCode;
  }
}

class ExerciseLoad {
  final int sets;
  final int? reps;

  /// in seconds for duration-based exercises
  final int? duration;
  final ExerciseLoadType type;

  const ExerciseLoad({required this.sets, this.reps, this.duration, required this.type});

  factory ExerciseLoad.fromJson(Map<String, dynamic> json) {
    return ExerciseLoad(
      sets: json['sets'] as int,
      reps: json['reps'] as int?,
      duration: json['duration'] as int?,
      type: ExerciseLoadType.fromString(json['type'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {'sets': sets, 'reps': reps, 'duration': duration, 'type': type.name};
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ExerciseLoad &&
        other.sets == sets &&
        other.reps == reps &&
        other.duration == duration &&
        other.type == type;
  }

  @override
  int get hashCode {
    return sets.hashCode ^ reps.hashCode ^ duration.hashCode ^ type.hashCode;
  }
}

enum ExerciseLoadType {
  reps,
  duration;

  static ExerciseLoadType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'reps':
        return ExerciseLoadType.reps;
      case 'duration':
        return ExerciseLoadType.duration;
      default:
        throw ArgumentError('Invalid ExerciseLoadType value: $value');
    }
  }
}
