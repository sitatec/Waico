import 'dart:convert';

class WorkoutSetupData {
  // Physical stats
  final double? weight;
  final double? height;
  final int? age;
  final String? gender;

  // Fitness level
  final String? currentFitnessLevel;
  // final int weeklyWorkoutFrequency;
  final List<String> selectedWeekDays;

  // Goals
  final String? primaryGoal;
  final String? targetWeight;
  final String? timeframe;
  final List<String> specificGoals;

  // Additional preferences
  final List<String> availableEquipment;
  final int workoutDurationPreference; // in minutes
  final String? experienceLevel;

  const WorkoutSetupData({
    this.weight,
    this.height,
    this.age,
    this.gender,
    this.currentFitnessLevel,
    this.selectedWeekDays = const ["Monday", "Wednesday", "Friday"],
    this.primaryGoal,
    this.targetWeight,
    this.timeframe,
    this.specificGoals = const [],
    this.availableEquipment = const [],
    this.workoutDurationPreference = 30,
    this.experienceLevel,
  });

  WorkoutSetupData copyWith({
    double? weight,
    double? height,
    int? age,
    String? gender,
    String? currentFitnessLevel,
    int? weeklyWorkoutFrequency,
    List<String>? selectedWeekDays,
    String? primaryGoal,
    String? targetWeight,
    String? timeframe,
    List<String>? specificGoals,
    List<String>? availableEquipment,
    int? workoutDurationPreference,
    String? experienceLevel,
  }) {
    return WorkoutSetupData(
      weight: weight ?? this.weight,
      height: height ?? this.height,
      age: age ?? this.age,
      gender: gender ?? this.gender,
      currentFitnessLevel: currentFitnessLevel ?? this.currentFitnessLevel,
      selectedWeekDays: selectedWeekDays ?? this.selectedWeekDays,
      primaryGoal: primaryGoal ?? this.primaryGoal,
      targetWeight: targetWeight ?? this.targetWeight,
      timeframe: timeframe ?? this.timeframe,
      specificGoals: specificGoals ?? this.specificGoals,
      availableEquipment: availableEquipment ?? this.availableEquipment,
      workoutDurationPreference: workoutDurationPreference ?? this.workoutDurationPreference,
      experienceLevel: experienceLevel ?? this.experienceLevel,
    );
  }

  bool get isComplete {
    // Check if all required fields are filled
    return weight != null &&
        height != null &&
        age != null &&
        gender != null &&
        currentFitnessLevel != null &&
        primaryGoal != null &&
        experienceLevel != null;
  }

  double? get bmi {
    if (weight != null && height != null && height! > 0) {
      final heightInMeters = height! / 100;
      return weight! / (heightInMeters * heightInMeters);
    }
    return null;
  }

  /// Convert from JSON Map
  factory WorkoutSetupData.fromJson(Map<String, dynamic> json) {
    return WorkoutSetupData(
      weight: json['weight']?.toDouble(),
      height: json['height']?.toDouble(),
      age: json['age']?.toInt(),
      gender: json['gender'],
      currentFitnessLevel: json['currentFitnessLevel'],
      selectedWeekDays: List<String>.from(json['selectedWeekDays'] ?? []),
      primaryGoal: json['primaryGoal'],
      targetWeight: json['targetWeight'],
      timeframe: json['timeframe'],
      specificGoals: List<String>.from(json['specificGoals'] ?? []),
      availableEquipment: List<String>.from(json['availableEquipment'] ?? []),
      workoutDurationPreference: json['workoutDurationPreference'] ?? 30,
      experienceLevel: json['experienceLevel'],
    );
  }

  /// Convert to JSON Map
  Map<String, dynamic> toJson() {
    return {
      'weight': weight,
      'height': height,
      'age': age,
      'gender': gender,
      'currentFitnessLevel': currentFitnessLevel,
      'selectedWeekDays': selectedWeekDays,
      'primaryGoal': primaryGoal,
      'targetWeight': targetWeight,
      'timeframe': timeframe,
      'specificGoals': specificGoals,
      'availableEquipment': availableEquipment,
      'workoutDurationPreference': workoutDurationPreference,
      'experienceLevel': experienceLevel,
    };
  }

  /// Convert from JSON string
  factory WorkoutSetupData.fromJsonString(String jsonString) {
    return WorkoutSetupData.fromJson(json.decode(jsonString));
  }

  /// Convert to JSON string
  String toJsonString() {
    return json.encode(toJson());
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is WorkoutSetupData &&
        other.weight == weight &&
        other.height == height &&
        other.age == age &&
        other.gender == gender &&
        other.currentFitnessLevel == currentFitnessLevel &&
        other.selectedWeekDays == selectedWeekDays &&
        other.primaryGoal == primaryGoal &&
        other.targetWeight == targetWeight &&
        other.timeframe == timeframe &&
        other.specificGoals == specificGoals &&
        other.availableEquipment == availableEquipment &&
        other.workoutDurationPreference == workoutDurationPreference &&
        other.experienceLevel == experienceLevel;
  }

  @override
  int get hashCode {
    return weight.hashCode ^
        height.hashCode ^
        age.hashCode ^
        gender.hashCode ^
        currentFitnessLevel.hashCode ^
        selectedWeekDays.hashCode ^
        primaryGoal.hashCode ^
        targetWeight.hashCode ^
        timeframe.hashCode ^
        specificGoals.hashCode ^
        availableEquipment.hashCode ^
        workoutDurationPreference.hashCode ^
        experienceLevel.hashCode;
  }
}
